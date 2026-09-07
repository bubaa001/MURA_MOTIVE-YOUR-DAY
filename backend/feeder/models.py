"""TheFeeder models: the human review queue.

Book upload / AI extraction was intentionally erased — the studio is a
human content pipeline: write -> review -> approve -> sync -> live.
"""

from django.conf import settings
from django.db import models


class ExtractedItem(models.Model):
    """One human-authored candidate awaiting the review pass."""

    TYPE_CHOICES = [
        ("quote", "Quote"),
        ("motion_quote", "Motion Quote"),
        ("prayer", "Prayer"),
        ("philosophy", "Philosophy"),
        ("word_of_the_day", "Word of the Day"),
        ("journal_story", "Journal Story"),
        ("spiritual_insight", "Spiritual Insight"),
    ]
    REVIEW_CHOICES = [
        ("pending", "Pending"),
        ("approved", "Approved"),
        ("rejected", "Rejected"),
    ]

    type = models.CharField(max_length=30, choices=TYPE_CHOICES)
    text = models.TextField()
    source = models.CharField(max_length=255)  # author, book title, or scripture ref
    year = models.PositiveSmallIntegerField(null=True, blank=True)
    tags = models.JSONField(default=list, blank=True)
    image = models.ImageField(upload_to="feeder/items/%Y/%m/", null=True, blank=True)
    image_url = models.URLField(blank=True)
    review_status = models.CharField(max_length=20, choices=REVIEW_CHOICES, default="pending")
    synced = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    # Audit trail: who wrote, reviewed, and when. Previously a "human review
    # pipeline" had zero accountability fields.
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="feeder_submissions",
    )
    reviewed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="feeder_reviews",
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    note = models.CharField(max_length=255, blank=True)  # e.g. rejection reason

    class Meta:
        ordering = ("-created_at", "-id")
        indexes = [
            models.Index(fields=("review_status",), name="feeder_item_status_idx"),
            models.Index(fields=("type",), name="feeder_item_type_idx"),
        ]

    def __str__(self) -> str:
        snippet = self.text[:60] + ("…" if len(self.text) > 60 else "")
        return f"[{self.type}/{self.review_status}] {snippet}"
