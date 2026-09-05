from rest_framework import serializers

from .models import NotificationLog, Reminder


def _validate_days(days):
    if not isinstance(days, list) or any(not isinstance(d, int) or not 0 <= d <= 6 for d in days):
        raise serializers.ValidationError("days must be a list of ints 0-6 (Mon=0), empty means daily.")
    return days


class ReminderSerializer(serializers.ModelSerializer):
    days = serializers.JSONField(required=False)
    time = serializers.TimeField(format="%H:%M")

    class Meta:
        model = Reminder
        fields = ("id", "title", "message", "time", "days", "category", "is_active", "created_at")
        read_only_fields = ("id", "created_at")

    def validate_days(self, value):
        return _validate_days(value)


class NotificationLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = NotificationLog
        fields = ("id", "title", "body", "kind", "created_at", "read_at")
        read_only_fields = ("id", "title", "body", "kind", "created_at")
