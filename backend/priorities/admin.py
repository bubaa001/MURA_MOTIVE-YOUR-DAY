from django.contrib import admin

from .models import Priority


@admin.register(Priority)
class PriorityAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "category", "order", "completed", "date")
    list_filter = ("completed", "category")
    search_fields = ("title", "user__username")
