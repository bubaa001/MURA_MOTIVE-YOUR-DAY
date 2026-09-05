from django.contrib import admin

from .models import Goal


@admin.register(Goal)
class GoalAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "category", "status", "progress", "target_date")
    list_filter = ("status",)
    search_fields = ("title", "user__username")
