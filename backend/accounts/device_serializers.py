from rest_framework import serializers

from .models import DeviceToken


class DeviceTokenSerializer(serializers.ModelSerializer):
    """Registration payloads for the mobile app's FCM token.

    The token is unique in the DB, but the serializer must NOT enforce it:
    perform_create() treats a known token as a re-register (upsert that
    re-activates the row), which a UniqueValidator would reject first.
    """

    class Meta:
        model = DeviceToken
        fields = ("id", "token", "platform", "is_active", "created_at")
        read_only_fields = ("id", "is_active", "created_at")
        extra_kwargs = {"token": {"validators": []}}
