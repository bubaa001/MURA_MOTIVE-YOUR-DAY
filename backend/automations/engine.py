"""Automation engine: dispatch events to matching rules.

Reactive flow: the triggering view calls fire_event() AFTER its atomic
block commits — the same discipline the codebase already follows for
NotificationLog/push side effects. Everything here is best-effort: a
broken rule must never fail a habit toggle or a goal completion.
"""

from __future__ import annotations

import logging

from django.utils import timezone

from habits.models import Habit, HabitLog
from habits.services import scheduled_days
from push.notify import notify_user
from reminders.models import NotificationLog

from .models import AutomationRule

logger = logging.getLogger(__name__)

# Templates may reference these; missing context renders as empty string.
_PLACEHOLDERS = ("habit", "streak", "goal")


def _render(template: str, context: dict[str, str]) -> str:
    text = template or ""
    for key in _PLACEHOLDERS:
        text = text.replace("{" + key + "}", context.get(key, ""))
    return text


def day_complete(user) -> bool:
    """True when every habit scheduled for today is completed (or the user
    has no scheduled habits — an empty checklist is vacuously complete,
    but a celebration for zero habits is noise, so it reports False)."""
    today = timezone.localdate()
    habits = [
        habit
        for habit in Habit.objects.filter(user=user, is_active=True)
        if today.isoweekday() in scheduled_days(habit)
    ]
    if not habits:
        return False
    done = set(
        HabitLog.objects.filter(
            habit__in=habits, date=today, completed=True
        ).values_list("habit_id", flat=True)
    )
    return all(habit.id in done for habit in habits)


def _matches(rule: AutomationRule, *, habit=None, streak=None, goal=None) -> bool:
    cfg = rule.trigger_config or {}
    trigger = rule.trigger_type
    if trigger in ("habit_done", "streak_reached"):
        wanted = cfg.get("habit_id")
        if wanted is not None and (habit is None or habit.id != wanted):
            return False
    if trigger == "streak_reached":
        # "Hits N" = exactly N: streaks move one day at a time via toggles,
        # so equality is the single crossing moment.
        if streak is None or streak != (cfg.get("streak") or 0):
            return False
    if trigger == "goal_achieved":
        wanted = cfg.get("goal_id")
        if wanted is not None and (goal is None or goal.id != wanted):
            return False
    return True


def _fire(rule: AutomationRule, *, habit=None, streak=None, goal=None) -> None:
    context = {
        "habit": habit.name if habit is not None else "",
        "streak": str(streak) if streak is not None else "",
        "goal": goal.title if goal is not None else "",
    }
    cfg = rule.action_config or {}
    title = _render(cfg.get("title") or rule.name, context)[:120]
    body = _render(cfg.get("body") or "", context)[:280]
    NotificationLog.objects.create(
        user=rule.user, title=title, body=body, kind="automation"
    )
    notify_user(
        rule.user,
        title,
        body,
        payload={"kind": "automation", "ruleId": rule.id},
    )
    rule.last_fired_date = timezone.localdate()
    rule.save(update_fields=["last_fired_date", "updated_at"])


def fire_event(user, event: str, *, habit=None, streak=None, goal=None) -> int:
    """Dispatch one reactive event to the user's matching rules.

    Returns how many rules fired (0 when none match); never raises — a
    rule failure must never break the API call that triggered it.
    """
    fired = 0
    today = timezone.localdate()
    try:
        rules = AutomationRule.objects.filter(
            user=user, trigger_type=event, is_active=True
        )
        for rule in rules:
            if not _matches(rule, habit=habit, streak=streak, goal=goal):
                continue
            if rule.last_fired_date == today:
                # Once per day per rule: toggle-off-then-on must not re-celebrate.
                continue
            _fire(rule, habit=habit, streak=streak, goal=goal)
            fired += 1
    except Exception:
        logger.exception("automation dispatch failed for event=%s user=%s", event, user)
    return fired
