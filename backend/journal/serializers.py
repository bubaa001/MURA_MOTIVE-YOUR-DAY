from rest_framework import serializers

from .models import JournalEntry, Memory


class JournalEntrySerializer(serializers.ModelSerializer):
    # Contract: mood is an enum or null. The model stores "" for none,
    # so translate both directions here.
    mood = serializers.ChoiceField(
        choices=JournalEntry.MOODS, allow_null=True, required=False
    )

    class Meta:
        model = JournalEntry
        fields = ("id", "title", "body", "mood", "created_at", "updated_at")
        read_only_fields = ("id", "created_at", "updated_at")

    def validate_mood(self, value):
        return value or ""

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if data.get("mood") == "":
            data["mood"] = None
        return data


class MemorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Memory
        fields = ("id", "title", "description", "date", "photo", "created_at")
        read_only_fields = ("id", "created_at")
