from django.conf import settings
from django.db import models


class Goal(models.Model):
    TYPE_CHOICES = [
        ("chief_aim", "Definite chief aim"),
        ("economic", "Economic"),
        ("things", "Things"),
        ("personal_development", "Personal development"),
    ]
    HORIZON_CHOICES = [
        ("short", "Short range"),
        ("long", "Long range"),
    ]
    STATUS = [
        ("active", "Active"),
        ("achieved", "Achieved"),
        ("abandoned", "Abandoned"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="goals")
    title = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    goal_type = models.CharField(max_length=30, choices=TYPE_CHOICES, default="personal_development")
    horizon = models.CharField(max_length=10, choices=HORIZON_CHOICES, default="short")
    category = models.CharField(max_length=60, blank=True)
    target_date = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS, default="active", db_index=True)
    progress = models.PositiveSmallIntegerField(default=0)
    linked_habits = models.ManyToManyField("habits.Habit", blank=True, related_name="goals")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return self.title
