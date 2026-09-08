"""Device registration for FCM pushes, mounted at /api/v1/me/devices/."""
from rest_framework import status, viewsets
from rest_framework.response import Response

from .device_serializers import DeviceTokenSerializer
from .models import DeviceToken


class DeviceTokenViewSet(viewsets.ModelViewSet):
    """/me/devices/ — register/list/remove this account's push devices.

    The mobile app POSTs its Firebase token after sign-in; a re-POST of a
    known token just refreshes it (idempotent upsert), so app updates and
    reinstalls never create dead duplicates. DELETE (or logout elsewhere)
    removes the row so pushes stop targeting a signed-out device.
    """

    serializer_class = DeviceTokenSerializer
    http_method_names = ("get", "post", "delete", "head", "options")

    def get_queryset(self):
        return DeviceToken.objects.filter(user=self.request.user, is_active=True)

    def perform_create(self, serializer):
        token = serializer.validated_data["token"]
        # Upsert: same physical device re-registering after app restart or
        # token rotation — reactivate the existing row instead of racing
        # the unique constraint.
        DeviceToken.objects.update_or_create(
            token=token,
            defaults={
                "user": self.request.user,
                "platform": serializer.validated_data.get("platform", "android"),
                "is_active": True,
            },
        )

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        row = DeviceToken.objects.filter(token=serializer.validated_data["token"]).first()
        return Response(
            self.get_serializer(row).data, status=status.HTTP_201_CREATED
        )

    def perform_destroy(self, instance):
        # Soft-delete: keeps the unique token row so a later re-register is
        # still an update, but stops it receiving pushes.
        instance.is_active = False
        instance.save(update_fields=["is_active", "updated_at"])
