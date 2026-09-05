from django.contrib import admin

from .models import Reminder


@admin.register(Reminder)
class ReminderAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "time", "days", "category", "is_active")
    list_filter = ("category", "is_active")
    search_fields = ("title", "message", "user__username")
