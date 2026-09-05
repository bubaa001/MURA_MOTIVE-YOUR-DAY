from django.contrib import admin

from .models import Habit, HabitLog


class HabitLogInline(admin.TabularInline):
    model = HabitLog
    extra = 0


@admin.register(Habit)
class HabitAdmin(admin.ModelAdmin):
    list_display = ("name", "user", "category", "color", "grace_days_per_week", "is_active", "created_at")
    list_filter = ("category", "color", "is_active")
    search_fields = ("name", "user__username")
    inlines = [HabitLogInline]


@admin.register(HabitLog)
class HabitLogAdmin(admin.ModelAdmin):
    list_display = ("habit", "user_email", "date", "completed")
    list_filter = ("completed",)
    search_fields = ("habit__name", "habit__user__username")

    @admin.display(description="User")
    def user_email(self, obj: HabitLog):
        return obj.habit.user.username
