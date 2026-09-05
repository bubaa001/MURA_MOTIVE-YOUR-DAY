import datetime as dt

from django.db import connection
from django.db.models import Count, Exists, F, OuterRef, Q, Value
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.response import Response

from .models import ContentEngagement, ContentItem
from .permissions import ServiceKeyPermission
from .serializers import ContentItemSerializer, ContentManageSerializer


class ContentItemViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Read-only feedable content: /api/v1/content/items/?type=quote&tag=discipline"""

    serializer_class = ContentItemSerializer
    permission_classes = (IsAuthenticated,)
    search_fields = ("text", "source")
    ordering_fields = ("created_at",)

    @action(
        detail=True,
        methods=["post", "delete"],
        permission_classes=(IsAdminUser,),
        parser_classes=(MultiPartParser, FormParser),
    )
    def image(self, request, pk=None):
        """Staff-only multipart upload/delete for a content item's artwork."""
        item = self.get_object()
        if request.method == "DELETE":
            item.image.delete(save=False)
            item.image = None
            item.save(update_fields=["image"])
            return Response(ContentItemSerializer(item, context={"request": request}).data)

        upload = request.FILES.get("image")
        if upload is None:
            return Response(
                {"image": ["This file is required."]},
                status=status.HTTP_400_BAD_REQUEST,
            )
        serializer = self.get_serializer(
            item,
            data={"image": upload},
            partial=True,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def get_queryset(self):
        engagement = ContentEngagement.objects.filter(
            item=OuterRef("pk"), user=self.request.user
        )
        qs = ContentItem.objects.filter(status="published").annotate(
            view_count=Count("engagements", filter=Q(engagements__viewed_at__isnull=False)),
            like_count=Count("engagements", filter=Q(engagements__liked=True)),
            viewed=Exists(engagement.filter(viewed_at__isnull=False)),
            read=Exists(engagement.filter(read_at__isnull=False)),
            liked=Exists(engagement.filter(liked=True)),
            saved=Exists(engagement.filter(saved=True)),
        )
        params = self.request.query_params
        type_param = params.get("type")
        if type_param:
            qs = qs.filter(type=type_param)
        tag = params.get("tag")
        if tag:
            if connection.features.supports_json_field_contains:
                qs = qs.filter(tags__contains=[tag])
            else:
                # SQLite has no JSON containment operator: match whole tag
                # values against the parsed list instead (corpus is small).
                matching = [
                    pk
                    for pk, tags in qs.values_list("pk", "tags")
                    if isinstance(tags, list) and tag in tags
                ]
                qs = qs.filter(pk__in=matching)
        status_param = params.get("status")
        if status_param == "unread":
            qs = qs.filter(read=False)
        elif status_param == "read":
            qs = qs.filter(read=True)
        elif status_param == "unviewed":
            qs = qs.filter(viewed=False)
        elif status_param == "viewed":
            qs = qs.filter(viewed=True)
        elif status_param == "liked":
            qs = qs.filter(liked=True)
        elif status_param == "saved":
            qs = qs.filter(saved=True)
        sort = params.get("sort", "top")
        if sort == "most_viewed":
            qs = qs.order_by("-view_count", "-like_count", "-created_at", "-id")
        elif sort == "most_liked":
            qs = qs.order_by("-like_count", "-view_count", "-created_at", "-id")
        elif sort == "newest":
            qs = qs.order_by("-created_at", "-id")
        else:
            qs = qs.annotate(
                top_score=(
                    F("view_count") + F("like_count") * Value(3)
                )
            ).order_by("-top_score", "-created_at", "-id")
        return qs

    @action(detail=True, methods=["post"])
    def view(self, request, pk=None):
        item = self.get_object()
        ContentEngagement.objects.update_or_create(
            item=item,
            user=request.user,
            defaults={"viewed_at": timezone.now()},
        )
        return Response(ContentItemSerializer(self.get_queryset().get(pk=item.pk), context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def read(self, request, pk=None):
        item = self.get_object()
        ContentEngagement.objects.update_or_create(
            item=item,
            user=request.user,
            defaults={"read_at": timezone.now(), "viewed_at": timezone.now()},
        )
        return Response(ContentItemSerializer(self.get_queryset().get(pk=item.pk), context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def like(self, request, pk=None):
        item = self.get_object()
        engagement, _ = ContentEngagement.objects.get_or_create(item=item, user=request.user)
        engagement.liked = not engagement.liked
        engagement.save(update_fields=["liked"])
        return Response(ContentItemSerializer(self.get_queryset().get(pk=item.pk), context={"request": request}).data)

    @action(detail=True, methods=["post"])
    def save(self, request, pk=None):
        item = self.get_object()
        engagement, _ = ContentEngagement.objects.get_or_create(item=item, user=request.user)
        engagement.saved = not engagement.saved
        engagement.save(update_fields=["saved"])
        return Response(ContentItemSerializer(self.get_queryset().get(pk=item.pk), context={"request": request}).data)


VALID_CONTENT_TYPES = {choice for choice, _label in ContentItem._meta.get_field("type").choices}


@api_view(["POST"])
@permission_classes([ServiceKeyPermission])
def bulk_import(request):
    """POST /api/v1/content/items/bulk-import/  (X-Service-Key header).

    Body: {"items": [{"type", "text", "source", "tags"}, ...]}
    Bulk-creates ContentItems, skipping exact-text duplicates per type.
    """
    payload = request.data.get("items")
    if not isinstance(payload, list):
        return Response({"detail": 'Body must be {"items": [...]}.'}, status=status.HTTP_400_BAD_REQUEST)

    created = skipped_duplicates = invalid = 0
    seen_in_batch: set[tuple[str, str]] = set()
    rows = []
    for entry in payload:
        if not isinstance(entry, dict):
            invalid += 1
            continue
        item_type = str(entry.get("type", "")).strip()
        text = str(entry.get("text", "")).strip()
        if item_type not in VALID_CONTENT_TYPES or not text or len(text) > 10000:
            invalid += 1
            continue
        key = (item_type, text)
        if key in seen_in_batch or ContentItem.objects.filter(type=item_type, text=text).exists():
            skipped_duplicates += 1
            continue
        seen_in_batch.add(key)
        tags = entry.get("tags") or []
        if not isinstance(tags, list):
            tags = []
        rows.append(
            ContentItem(
                type=item_type,
                text=text,
                source=str(entry.get("source", "")).strip()[:255],
                tags=[str(t)[:50].lower() for t in tags],
            )
        )
    ContentItem.objects.bulk_create(rows)
    created = len(rows)
    return Response({"created": created, "skipped_duplicates": skipped_duplicates, "invalid": invalid})


def _rotated(type_name: str, date: dt.date, salt: int):
    """Deterministic daily pick: same date -> same item, rotates daily."""
    qs = ContentItem.objects.filter(type=type_name, status="published").order_by("id")
    count = qs.count()
    if count == 0:
        return None
    return qs[(date.toordinal() * 7 + salt) % count]


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def daily_feed(request):
    """/api/v1/content/daily/ -> {quote, insight, philosophy} for a date."""
    raw_date = request.query_params.get("date")
    try:
        day = dt.date.fromisoformat(raw_date) if raw_date else dt.date.today()
    except ValueError:
        return Response({"detail": "Invalid date, expected YYYY-MM-DD."}, status=400)

    def _slot(type_name: str, salt: int):
        item = _rotated(type_name, day, salt)
        return (
            ContentItemSerializer(item, context={"request": request}).data
            if item is not None
            else None
        )

    return Response(
        {
            "date": day.isoformat(),
            "quote": _slot("quote", 0),
            # Spiritual insight replaced the prayer slot (no prayers written).
            "insight": _slot("spiritual_insight", 3),
            "philosophy": _slot("philosophy", 5),
        }
    )


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def motion_feed(request):
    """Return the deterministic batch of up to ten motion quotes for a day."""
    raw_date = request.query_params.get("date")
    try:
        day = dt.date.fromisoformat(raw_date) if raw_date else dt.date.today()
    except ValueError:
        return Response({"detail": "Invalid date, expected YYYY-MM-DD."}, status=400)

    quotes = list(ContentItem.objects.filter(type="motion_quote", status="published").order_by("id"))
    if not quotes:
        return Response({"date": day.isoformat(), "items": []})
    batch_count = (len(quotes) + 9) // 10
    batch_index = day.toordinal() % batch_count
    batch = quotes[batch_index * 10 : (batch_index + 1) * 10]
    return Response(
        {
            "date": day.isoformat(),
            "items": ContentItemSerializer(
                batch, many=True, context={"request": request}
            ).data,
        }
    )
# ---------------------------------------------------------------------------
# Staff studio: full control over the app's content hub (TheFeeder dashboard)
# ---------------------------------------------------------------------------
class ContentManageViewSet(viewsets.ModelViewSet):
    """Full CRUD + lifecycle control over ContentItem for staff.

    GET    /api/v1/feeder/content/?type=&status=&q=   list (all statuses)
    POST   /api/v1/feeder/content/                    create (draft for staff)
    PATCH  /api/v1/feeder/content/{id}/               edit any field
    DELETE /api/v1/feeder/content/{id}/               permanently delete
    POST   /api/v1/feeder/content/bulk/               {ids, action}
    POST   /api/v1/feeder/content/{id}/image/         upload artwork (multipart)
    DELETE /api/v1/feeder/content/{id}/image/         remove artwork

    Publishing (status -> "published") is reserved for superusers; other staff
    can draft, edit, archive, and delete but never force content live.
    """

    serializer_class = ContentManageSerializer
    permission_classes = (IsAdminUser,)
    parser_classes = (JSONParser, MultiPartParser, FormParser)
    http_method_names = ("get", "post", "patch", "delete", "head", "options")

    def get_queryset(self):
        qs = ContentItem.objects.select_related("feeder_item").all()
        params = self.request.query_params
        type_param = params.get("type")
        if type_param:
            qs = qs.filter(type=type_param)
        status_param = params.get("status")
        if status_param in {choice for choice, _label in ContentItem.PUBLISH_STATUS}:
            qs = qs.filter(status=status_param)
        q = params.get("q", "").strip()
        if q:
            qs = qs.filter(Q(text__icontains=q) | Q(source__icontains=q))
        sort = params.get("sort", "updated")
        if sort == "oldest":
            qs = qs.order_by("id")
        elif sort == "type":
            qs = qs.order_by("type", "-updated_at", "-id")
        elif sort == "created":
            qs = qs.order_by("-created_at", "-id")
        else:
            qs = qs.order_by("-updated_at", "-id")
        return qs

    def _published_allowed(self, data):
        """Non-superusers may never force content live (queue-first rule)."""
        return self.request.user.is_superuser or data.get("status") != "published"

    def create(self, request, *args, **kwargs):
        if not self._published_allowed(request.data):
            request.data["status"] = "draft"
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        # Ignore a status->published attempt by non-superusers on PATCH/PUT.
        if not self.request.user.is_superuser and request.data.get("status") == "published":
            mutable = request.data
            if hasattr(mutable, "_mutable"):
                mutable._mutable = True
            mutable.pop("status", None)
        return super().update(request, *args, **kwargs)

    @action(detail=False, methods=["post"], url_path="bulk")
    def bulk(self, request):
        """POST {ids: [...], action: "archive"|"restore"|"draft"|"delete"}."""
        ids = request.data.get("ids") or []
        action = request.data.get("action")
        targets = {
            "archive": "archived",
            "restore": "published",
            "draft": "draft",
        }
        if action not in targets and action != "delete":
            return Response({"detail": 'action must be one of archive|restore|draft|delete.'}, status=400)
        if not isinstance(ids, list) or not ids:
            return Response({"detail": "ids must be a non-empty list."}, status=400)
        qs = ContentItem.objects.filter(id__in=ids)
        if action == "delete":
            count, _ = qs.delete()
            return Response({"deleted": count})
        if action == "restore" and not request.user.is_superuser:
            return Response({"detail": "Only the owner can restore (publish) content."}, status=403)
        count = qs.update(status=targets[action])
        return Response({"updated": count, "status": targets[action]})

    @action(
        detail=True,
        methods=["post", "delete"],
        parser_classes=(MultiPartParser, FormParser),
    )
    def image(self, request, pk=None):
        """Upload (POST, multipart 'image') or remove (DELETE) an item's artwork."""
        item = self.get_object()
        if request.method == "DELETE":
            item.image.delete(save=False)
            item.image = None
            item.save(update_fields=["image", "updated_at"])
            return Response(ContentManageSerializer(item, context={"request": request}).data)
        upload = request.FILES.get("image")
        if upload is None:
            return Response({"image": ["This file is required."]}, status=status.HTTP_400_BAD_REQUEST)
        item.image = upload
        item.image_url = ""
        item.save(update_fields=["image", "image_url", "updated_at"])
        return Response(ContentManageSerializer(item, context={"request": request}).data)

