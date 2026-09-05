from rest_framework import parsers, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .models import ExtractedItem
from .serializers import ExtractedItemSerializer, ManualSubmissionSerializer
from .services import sync_items


class ExtractedItemViewSet(viewsets.ModelViewSet):
    """/api/v1/feeder/items/?review_status=pending&type=quote (staff only)."""

    queryset = ExtractedItem.objects.all()
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
        updated = ExtractedItem.objects.filter(id__in=ids).update(review_status=target)
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
        )
        return Response(
            {"item": ExtractedItemSerializer(item).data},
            status=status.HTTP_201_CREATED,
        )

    @action(detail=False, methods=["post"])
    def sync(self, request):
        """Push all approved+unsynced items into the main app's ContentItem hub."""
        targets = list(ExtractedItem.objects.filter(review_status="approved", synced=False))
        synced = sync_items(targets) if targets else 0
        return Response({"submitted": len(targets), "synced": synced})
