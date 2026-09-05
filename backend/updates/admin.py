from django.contrib import admin

from .models import Release


@admin.register(Release)
class ReleaseAdmin(admin.ModelAdmin):
    list_display = ("version_name", "version_code", "created_at")
    readonly_fields = ("created_at",)
