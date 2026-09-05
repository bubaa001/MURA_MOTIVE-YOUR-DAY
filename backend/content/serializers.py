from rest_framework import serializers

from .models import ContentItem


def _resolve_image(item, request):
    """Shared artwork resolver: image_url wins, else the uploaded file."""
    if item.image_url:
        return item.image_url
    if not item.image:
        return None
    return request.build_absolute_uri(item.image.url) if request else item.image.url


class ContentItemSerializer(serializers.ModelSerializer):
    image = serializers.SerializerMethodField()
    view_count = serializers.IntegerField(read_only=True, default=0)
    like_count = serializers.IntegerField(read_only=True, default=0)
    viewed = serializers.BooleanField(read_only=True, default=False)
    read = serializers.BooleanField(read_only=True, default=False)
    liked = serializers.BooleanField(read_only=True, default=False)
    saved = serializers.BooleanField(read_only=True, default=False)

    def get_image(self, item):
        return _resolve_image(item, self.context.get("request"))

    class Meta:
        model = ContentItem
        fields = (
            "id", "type", "text", "source", "year", "tags", "image", "image_url", "created_at",
            "view_count", "like_count", "viewed", "read", "liked", "saved",
        )
        read_only_fields = ("id", "created_at")


class ContentManageSerializer(serializers.ModelSerializer):
    """Staff studio serializer: full control over every field of the content hub.

    image_file is a write-only multipart field for uploading artwork; the
    resolved image is always returned. provenance reports which TheFeeder
    candidate/book produced the item, when one exists.
    """

    image = serializers.SerializerMethodField()
    image_file = serializers.ImageField(write_only=True, required=False, allow_null=True)
    remove_image = serializers.BooleanField(write_only=True, required=False, default=False)
    provenance = serializers.SerializerMethodField()

    def get_image(self, item):
        return _resolve_image(item, self.context.get("request"))

    def get_provenance(self, item):
        feeder = getattr(item, "feeder_item", None)
        if feeder is None:
            return None
        return {
            "feeder_item_id": feeder.id,
            "book": feeder.source or None,
            "review_status": feeder.review_status,
        }

    def create(self, validated_data):
        image_file = validated_data.pop("image_file", None)
        validated_data.pop("remove_image", None)  # bool default always present
        item = super().create(validated_data)
        if image_file:
            item.image = image_file
            item.save(update_fields=["image"])
        return item

    def update(self, instance, validated_data):
        image_file = validated_data.pop("image_file", None)
        remove_image = validated_data.pop("remove_image", False)
        item = super().update(instance, validated_data)
        if image_file:
            item.image = image_file
            item.image_url = ""
        elif remove_image:
            item.image.delete(save=False)
            item.image = None
        item.save(update_fields=["image", "image_url", "updated_at"])
        return item

    class Meta:
        model = ContentItem
        fields = (
            "id", "type", "text", "source", "year", "tags", "status",
            "image", "image_url", "image_file", "remove_image",
            "created_at", "updated_at", "provenance",
        )
        read_only_fields = ("id", "created_at", "updated_at", "provenance")
