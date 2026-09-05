from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User


@admin.register(User)
class MuraUserAdmin(UserAdmin):
    list_display = (
        "username",
        "email",
        "display_name",
        "is_staff",
        "is_active",
        "date_joined",
    )
    list_filter = ("is_staff", "is_active", "is_superuser", "groups", "date_joined")
    search_fields = ("username", "email", "display_name", "first_name", "last_name")
    ordering = ("-date_joined",)
    fieldsets = UserAdmin.fieldsets + (("MURA", {"fields": ("display_name", "avatar")}),)
