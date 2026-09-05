from django.contrib import admin

from .models import ContentItem


@admin.register(ContentItem)
class ContentItemAdmin(admin.ModelAdmin):
    list_display = ("short_text", "type", "source", "has_image", "tag_list", "created_at")
    list_filter = ("type", "source")
    search_fields = ("text", "source")
    ordering = ("-created_at",)

    @admin.display(description="Text", ordering="text")
    def short_text(self, obj: ContentItem) -> str:
        return obj.text[:80]

    @admin.display(description="Tags")
    def tag_list(self, obj: ContentItem) -> str:
        return ", ".join(obj.tags) if isinstance(obj.tags, list) else ""

    @admin.display(boolean=True, description="Image")
    def has_image(self, obj: ContentItem) -> bool:
        return bool(obj.image)
