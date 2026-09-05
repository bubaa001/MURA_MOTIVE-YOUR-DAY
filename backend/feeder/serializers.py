from rest_framework import serializers

from .models import ExtractedItem


class ExtractedItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExtractedItem
        fields = ("id", "type", "text", "source", "year", "tags", "image", "image_url", "review_status", "synced", "created_at")
        read_only_fields = ("id", "synced", "created_at")


class ManualSubmissionSerializer(serializers.Serializer):
    """A human-authored candidate that follows the review-first flow."""

    type = serializers.ChoiceField(choices=ExtractedItem.TYPE_CHOICES)
    text = serializers.CharField(max_length=10_000, trim_whitespace=True)
    source = serializers.CharField(max_length=255, required=False, allow_blank=True, trim_whitespace=True)
    year = serializers.IntegerField(required=False, allow_null=True, min_value=0, max_value=2100)
    tags = serializers.ListField(
        child=serializers.CharField(max_length=50, trim_whitespace=True),
        required=False,
        allow_empty=True,
        max_length=5,
    )
    image = serializers.ImageField(required=False, allow_null=True)
    image_url = serializers.URLField(required=False, allow_blank=True)

    def validate_tags(self, tags):
        cleaned = []
        for tag in tags:
            normalized = tag.lower().replace(" ", "-")
            if normalized and normalized not in cleaned:
                cleaned.append(normalized)
        return cleaned
