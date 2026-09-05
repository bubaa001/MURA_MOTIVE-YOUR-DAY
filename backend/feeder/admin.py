from django.contrib import admin

from .models import ExtractedItem


@admin.register(ExtractedItem)
class ExtractedItemAdmin(admin.ModelAdmin):
    list_display = ("type", "review_status", "synced", "source", "created_at")
    list_filter = ("review_status", "type", "synced")
    search_fields = ("text", "source")
    readonly_fields = ("created_at",)
