from django.conf import settings
from django.db import models


class AutomationRule(models.Model):
    """One user-defined rule: WHEN trigger happens, THEN send this message.

    Reactive triggers (habit_done, all_habits_done, streak_reached,
    goal_achieved) fire inline right after the triggering API call; the
    time-based trigger (daily_nudge) is evaluated by the run_automations
    scheduled command (hourly, with a catch-up window and same-day dedup —
    the exact contract push_due_reminders established).
    """

    TRIGGERS = [
        ("habit_done", "A habit is completed"),
        ("all_habits_done", "All of today's habits are done"),
        ("streak_reached", "A streak reaches N days"),
        ("goal_achieved", "A goal is achieved"),
        ("daily_nudge", "Every day at a time (optional: only if habits incomplete)"),
    ]
    ACTIONS = [
        ("push", "Send me a notification"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="automations"
    )
    name = models.CharField(max_length=80)
    trigger_type = models.CharField(max_length=20, choices=TRIGGERS)
    # Config keys by trigger: habit_done {"habit_id": int|null}, all_habits_done {},
    # streak_reached {"streak": int, "habit_id": int|null}, goal_achieved {},
    # daily_nudge {"time": "HH:MM", "only_if_incomplete": bool}.
    trigger_config = models.JSONField(default=dict, blank=True)
    action_type = models.CharField(max_length=20, choices=ACTIONS, default="push")
    # Config keys: push {"title": str (may contain {habit}/{streak}/{goal}
    # placeholders), "body": str}.
    action_config = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)
    # Same-day dedup for daily_nudge (reactive triggers are naturally
    # single-shot per event, so they never touch this field).
    last_fired_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return f"{self.name} ({self.get_trigger_type_display()})"
