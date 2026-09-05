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
