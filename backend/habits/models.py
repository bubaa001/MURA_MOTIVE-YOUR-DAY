import datetime as dt

from django.conf import settings
from django.db import models


class Habit(models.Model):
    """A daily 'good practice' the user wants to stay accountable to."""

    CATEGORIES = [
        ("physical", "Physical"),
        ("mental", "Mental"),
        ("financial", "Financial"),
        ("spiritual", "Spiritual"),
    ]
    COLORS = [
        ("primary", "Amber"),
        ("secondary", "Teal"),
        ("tertiary", "Indigo"),
        ("error", "Coral"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="habits")
    name = models.CharField(max_length=120)
    description = models.CharField(max_length=255, blank=True)
    icon = models.CharField(max_length=40, default="check_circle", blank=True)
    color = models.CharField(max_length=20, choices=COLORS, default="primary")
    category = models.CharField(max_length=20, choices=CATEGORIES, default="mental")
    grace_days_per_week = models.PositiveSmallIntegerField(default=0)
    # ISO weekdays: Monday=1 through Sunday=7. An empty list is normalized to
    # every day by the API for backwards-compatible daily habits.
    schedule_days = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("created_at",)

    def __str__(self) -> str:
        return f"{self.name} ({self.user})"


class HabitLog(models.Model):
    """One row per habit per day touched. completed=False rows are kept so a
    toggle-off stays auditable; streak math only counts completed=True rows."""

    habit = models.ForeignKey(Habit, on_delete=models.CASCADE, related_name="logs")
    date = models.DateField(default=dt.date.today)
    completed = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=("habit", "date"), name="uniq_habit_day")
        ]
        ordering = ("-date",)

    def __str__(self) -> str:
        state = "done" if self.completed else "missed"
        return f"{self.habit.name} {state} {self.date}"
