from django.contrib import admin

from .models import AutomationRule


@admin.register(AutomationRule)
class AutomationRuleAdmin(admin.ModelAdmin):
    list_display = ("name", "user", "trigger_type", "is_active", "last_fired_date", "created_at")
    list_filter = ("trigger_type", "is_active")
    search_fields = ("name", "user__username")
