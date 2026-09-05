from django.conf import settings
from django.db import models


class JournalEntry(models.Model):
    MOODS = [
        ("great", "Great"),
        ("good", "Good"),
        ("neutral", "Neutral"),
        ("low", "Low"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="journal_entries")
    title = models.CharField(max_length=160, blank=True)
    body = models.TextField()
    mood = models.CharField(max_length=10, choices=MOODS, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)
        verbose_name_plural = "journal entries"

    def __str__(self) -> str:
        return self.title or f"{self.body[:50]}…"


class Memory(models.Model):
    """Achievement worth looking back on. Optional photo."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="memories")
    title = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    date = models.DateField()
    photo = models.ImageField(upload_to="memories/%Y/%m/", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-date", "-created_at")

    def __str__(self) -> str:
        return self.title
