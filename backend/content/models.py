from django.db import models


class ContentItem(models.Model):
    """One generic, feedable content record powering the whole Library hub.

    Quotes (Think and Grow Rich), prayers/devotionals (The Game of Life),
    and personal philosophies all share this shape so new material can be
    added from Django admin without a code change.
    """

    CONTENT_TYPES = [
        ("quote", "Quote"),
        ("motion_quote", "Motion Quote"),
        ("prayer", "Prayer"),
        ("philosophy", "Philosophy"),
        ("word_of_the_day", "Word of the Day"),
        ("journal_story", "Journal Story"),
        ("spiritual_insight", "Spiritual Insight"),
    ]

    PUBLISH_STATUS = [
        ("published", "Published"),
        ("draft", "Draft"),
        ("archived", "Archived"),
    ]

    type = models.CharField(max_length=30, choices=CONTENT_TYPES, db_index=True)
    text = models.TextField()
    source = models.CharField(max_length=255, blank=True)
    year = models.PositiveSmallIntegerField(null=True, blank=True)
    tags = models.JSONField(default=list, blank=True)
    image = models.ImageField(upload_to="content/%Y/%m/", null=True, blank=True)
    image_url = models.URLField(blank=True)
    # Lifecycle: published items are visible in the app; draft/archived are not.
    status = models.CharField(max_length=20, choices=PUBLISH_STATUS, default="published", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    # Provenance: which TheFeeder candidate produced this item (nullable for
    # items written straight into the app or imported via bulk-import).
    feeder_item = models.ForeignKey(
        "feeder.ExtractedItem",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="content_items",
    )

    class Meta:
        ordering = ("id",)
        indexes = [
            models.Index(fields=["type"]),
            models.Index(fields=["status"]),
            models.Index(fields=("type", "status"), name="content_type_status_idx"),
            # Composite that every tag-filtered listing actually needs.
            models.Index(fields=("status", "type"), name="content_status_type_idx"),
        ]

    def __str__(self) -> str:
        snippet = self.text[:60] + ("…" if len(self.text) > 60 else "")
        return f"[{self.type}] {snippet}"


class ContentEngagement(models.Model):
    """Per-user reading and like state for a published content item."""

    item = models.ForeignKey(
        ContentItem, on_delete=models.CASCADE, related_name="engagements"
    )
    user = models.ForeignKey(
        "accounts.User", on_delete=models.CASCADE, related_name="content_engagements"
    )
    viewed_at = models.DateTimeField(null=True, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    liked = models.BooleanField(default=False)
    saved = models.BooleanField(default=False)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=("item", "user"), name="unique_content_engagement"
            )
        ]
        indexes = [
            models.Index(
                fields=("item", "liked"), name="content_con_item_id_29a3e4_idx"
            ),
            models.Index(
                fields=("item", "viewed_at"), name="content_con_item_id_0d58fa_idx"
            ),
        ]


class SiteSetting(models.Model):
    """Single-row-per-key studio setting (TheFeeder). Key/value with a sane
    default in code, so the feeder can tune the app without a deploy."""

    key = models.CharField(max_length=60, unique=True)
    value = models.CharField(max_length=200)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "site setting"

    def __str__(self) -> str:
        return f"{self.key}={self.value}"


def get_setting(key: str, default: str) -> str:
    """Read a SiteSetting with a code default; never raises."""
    row = SiteSetting.objects.filter(key=key).first()
    return row.value if row is not None else default
