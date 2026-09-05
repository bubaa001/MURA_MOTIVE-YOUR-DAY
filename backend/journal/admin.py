from django.contrib import admin

from .models import JournalEntry, Memory


@admin.register(JournalEntry)
class JournalEntryAdmin(admin.ModelAdmin):
    list_display = ("short_body", "user", "mood", "created_at")
    search_fields = ("title", "body", "user__username")

    @admin.display(description="Body")
    def short_body(self, obj: JournalEntry) -> str:
        return obj.title or obj.body[:70]


@admin.register(Memory)
class MemoryAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "date", "has_photo")
    date_hierarchy = "date"
    search_fields = ("title", "description", "user__username")

    @admin.display(description="Photo", boolean=True)
    def has_photo(self, obj: Memory) -> bool:
        return bool(obj.photo)
