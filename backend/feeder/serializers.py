from rest_framework import serializers

from .models import ExtractedItem


def _resolve_image(item, request):
    """image_url wins, else the uploaded file — as an ABSOLUTE URL. The
    studio is hosted on another origin, so a relative /media/... path 404s."""
    if item.image_url:
        return item.image_url
    if not item.image:
        return None
    return request.build_absolute_uri(item.image.url) if request else item.image.url


class ExtractedItemSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    submitted_by_name = serializers.CharField(source="submitted_by.username", read_only=True, default=None)
    reviewed_by_name = serializers.CharField(source="reviewed_by.username", read_only=True, default=None)

    def get_image(self, item):
        return _resolve_image(item, self.context.get("request"))

    class Meta:
        model = ExtractedItem
        fields = (
            "id", "type", "text", "source", "year", "tags", "image", "image_url",
            "review_status", "synced", "created_at", "updated_at",
            "submitted_by", "submitted_by_name", "reviewed_by", "reviewed_by_name",
            "reviewed_at", "note",
        )
        read_only_fields = ("id", "synced", "created_at", "updated_at", "submitted_by", "reviewed_by", "reviewed_at")


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

    def update(self, instance, validated_data):
        """PATCH through the same shape: edit an existing candidate."""
        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save()
        return instance
