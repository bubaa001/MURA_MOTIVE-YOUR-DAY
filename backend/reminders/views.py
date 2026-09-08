from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import NotificationLog, Reminder
from .serializers import NotificationLogSerializer, ReminderSerializer


class ReminderViewSet(viewsets.ModelViewSet):
    serializer_class = ReminderSerializer

    def get_queryset(self):
        return Reminder.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class NotificationViewSet(mixins.ListModelMixin, viewsets.GenericViewSet):
    """GET /notifications/ - the user's pushed-event feed (newest first).

    POST /notifications/read_all/ - mark everything read (called when the
    user opens the notification panel).

    DELETE /notifications/clear/  - empty the feed (?read_only=1 keeps
    unread items, the default clears everything).
    """

    serializer_class = NotificationLogSerializer

    def get_queryset(self):
        return NotificationLog.objects.filter(user=self.request.user)

    @action(detail=False, methods=["post"])
    def read_all(self, request):
        updated = NotificationLog.objects.filter(user=request.user, read_at__isnull=True).update(
            read_at=timezone.now()
        )
        return Response({"marked": updated}, status=status.HTTP_200_OK)

    @action(detail=False, methods=["delete", "post"])
    def clear(self, request):
        """Delete the caller's notifications. ?read_only=1 keeps unread."""
        qs = NotificationLog.objects.filter(user=request.user)
        if request.query_params.get("read_only") in ("1", "true", "yes"):
            qs = qs.filter(read_at__isnull=False)
        deleted, _ = qs.delete()
        return Response({"cleared": deleted}, status=status.HTTP_200_OK)
