from django.conf import settings
from django.db import models


class Reminder(models.Model):
    """A user-configurable nudge (time/frequency/message). Phase 2 will also
    push these server-side via the Expo push API; Phase 1 schedules locally."""

    CATEGORIES = [
        ("health", "Health"),
        ("mental", "Mental discipline"),
        ("financial", "Financial"),
        ("progress", "Personal progress"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reminders")
    title = models.CharField(max_length=120)
    message = models.CharField(max_length=280, blank=True)
    time = models.TimeField()
    days = models.JSONField(default=list, blank=True, help_text="0=Mon..6=Sun. Empty list means every day.")
    category = models.CharField(max_length=20, choices=CATEGORIES, default="progress")
    is_active = models.BooleanField(default=True)
    last_pushed_date = models.DateField(null=True, blank=True, help_text="Last date this reminder was pushed via FCM (dedup for the push loop).")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("time",)

    def __str__(self) -> str:
        return f"{self.title} @ {self.time:%H:%M}"


class PushCampaign(models.Model):
    """A broadcast push composed in TheFeeder and sent to every device via
    FCM (Google) — either immediately or on a natural schedule (daily
    morning / chosen weekday such as Sunday)."""

    SCHEDULES = [
        ("now", "Send once, now"),
        ("daily", "Daily (every morning)"),
        ("weekly", "Weekly (chosen day)"),
    ]
    WEEKDAYS = [
        (0, "Monday"), (1, "Tuesday"), (2, "Wednesday"), (3, "Thursday"),
        (4, "Friday"), (5, "Saturday"), (6, "Sunday"),
    ]

    title = models.CharField(max_length=120)
    body = models.CharField(max_length=500, blank=True)
    schedule = models.CharField(max_length=10, choices=SCHEDULES, default="now")
    send_time = models.TimeField(default="06:30", help_text="Time of day for daily/weekly sends.")
    weekday = models.PositiveSmallIntegerField(null=True, blank=True, choices=WEEKDAYS, help_text="Weekly only.")
    is_active = models.BooleanField(default=True)
    last_sent_date = models.DateField(null=True, blank=True, help_text="Dedupes same-day sends.")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return self.title


class NotificationLog(models.Model):
    """One pushed event, kept so the app can show a notification feed."""

    KINDS = [
        ("reminder", "Reminder"),
        ("streak_milestone", "Streak milestone"),
        ("goal_achieved", "Goal achieved"),
        ("automation", "Automation"),
        ("general", "General"),
    ]

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="notifications")
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=280, blank=True)
    kind = models.CharField(max_length=20, choices=KINDS, default="general")
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return self.title

