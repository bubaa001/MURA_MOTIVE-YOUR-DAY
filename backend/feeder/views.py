from django.utils import timezone
from rest_framework import parsers, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .models import ExtractedItem
from .serializers import ExtractedItemSerializer, ManualSubmissionSerializer
from .services import sync_items


class ExtractedItemViewSet(viewsets.ModelViewSet):
    """/api/v1/feeder/items/?review_status=pending&type=quote (staff only)."""

    queryset = ExtractedItem.objects.select_related("submitted_by", "reviewed_by").all()
    serializer_class = ExtractedItemSerializer
    permission_classes = (IsAdminUser,)
    parser_classes = (parsers.MultiPartParser, parsers.FormParser, parsers.JSONParser)
    http_method_names = ("get", "post", "patch", "delete", "head", "options")

    def get_queryset(self):
        qs = super().get_queryset()
        params = self.request.query_params
        for param in ("review_status", "type"):
            value = params.get(param)
            if value:
                qs = qs.filter(**{param: value})
        return qs

    @action(detail=False, methods=["post"], url_path="bulk-review")
    def bulk_review(self, request):
        """POST {ids: [...], review_status: "approved"|"rejected"}."""
        ids = request.data.get("ids") or []
        target = request.data.get("review_status")
        if target not in ("approved", "rejected"):
            return Response({"detail": 'review_status must be "approved" or "rejected".'}, status=400)
        if not isinstance(ids, list) or not ids:
            return Response({"detail": "ids must be a non-empty list."}, status=400)
        updated = ExtractedItem.objects.filter(id__in=ids).update(
            review_status=target,
            reviewed_by=request.user if request.user.is_authenticated else None,
            reviewed_at=timezone.now(),
        )
        return Response({"updated": updated})

    @action(detail=False, methods=["post"], url_path="manual-submit")
    def manual_submit(self, request):
        """Queue one person-submitted item for review; it never bypasses approval."""
        serializer = ManualSubmissionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        item = ExtractedItem.objects.create(
            type=data["type"],
            text=data["text"],
            source=data.get("source") or "Community submission",
            year=data.get("year"),
            tags=data.get("tags", []),
            image=data.get("image"),
            image_url=data.get("image_url", ""),
            review_status="pending",
            submitted_by=request.user if request.user.is_authenticated else None,
        )
        return Response(
            {"item": ExtractedItemSerializer(item, context={"request": request}).data},
            status=status.HTTP_201_CREATED,
        )

    def _sync_response(self, request, targets):
        if not targets:
            return Response({"submitted": 0, "synced": 0, "results": []})
        report = sync_items(targets)
        synced = sum(1 for entry in report.values() if entry["ok"] and entry["created"])
        results = [
            {"item_id": item_id, **entry} for item_id, entry in report.items()
        ]
        return Response({"submitted": len(targets), "synced": synced, "results": results})

    @action(detail=False, methods=["post"])
    def sync(self, request):
        """Push all approved+unsynced items live. Superuser only: sync creates
        ContentItems with status=published, which is the publish action the
        content studio reserves for the owner (IsAdminUser would let any
        staff member force content live)."""
        if not request.user.is_superuser:
            return Response(
                {"detail": "Only the owner can sync content live."},
                status=status.HTTP_403_FORBIDDEN,
            )
        targets = list(ExtractedItem.objects.filter(review_status="approved", synced=False))
        return self._sync_response(request, targets)

    @action(detail=True, methods=["post"])
    def sync_item(self, request, pk=None):
        """Push exactly one approved candidate live (superuser only)."""
        if not request.user.is_superuser:
            return Response(
                {"detail": "Only the owner can sync content live."},
                status=status.HTTP_403_FORBIDDEN,
            )
        item = self.get_object()
        if item.review_status != "approved":
            return Response(
                {"detail": "Only approved items can be synced."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return self._sync_response(request, [item])

    @action(detail=True, methods=["post"], url_path="unsync")
    def unsync(self, request, pk=None):
        """Reset a candidate's synced flag so it can be re-synced after its
        live copy was deleted (superuser only)."""
        if not request.user.is_superuser:
            return Response(
                {"detail": "Only the owner can unsync candidates."},
                status=status.HTTP_403_FORBIDDEN,
            )
        item = self.get_object()
        item.synced = False
        item.save(update_fields=("synced",))
        return Response(ExtractedItemSerializer(item, context={"request": request}).data)
