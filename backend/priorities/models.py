import datetime as dt

from django.conf import settings
from django.db import models


class Priority(models.Model):
    """One focused task for a given day, manually ordered."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="priorities")
    title = models.CharField(max_length=200)
    category = models.CharField(max_length=40, default="Deep Work")
    order = models.PositiveIntegerField(default=0)
    completed = models.BooleanField(default=False)
    date = models.DateField(default=dt.date.today, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("order", "created_at")

    def __str__(self) -> str:
        return f"{self.order}. {self.title} ({self.date})"
