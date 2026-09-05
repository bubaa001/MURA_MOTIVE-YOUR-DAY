"""Streak & heatmap math for MURA.

Grace-day semantics (documented behaviour):

* A missed day does NOT break a streak if it can be "forgiven".
* Forgiveness budget is habit.grace_days_per_week inside a rolling
  7-day window; a forgiven miss consumes one unit until it ages out.
* Two consecutive missed days are NEVER forgiven - the second one breaks
  the streak regardless of budget (discipline with mercy, not excuses).
* Today with no log yet is "pending", not broken: streak scans stop at
  yesterday when today is unchecked.
"""
from __future__ import annotations

import datetime as dt
from collections import deque

from django.utils import timezone

from .models import Habit, HabitLog

DAY = dt.timedelta(days=1)


def _local_today() -> dt.date:
    return timezone.localdate()


def _start_date(habit: Habit) -> dt.date:
    return timezone.localdate(habit.created_at)


def scheduled_days(habit: Habit) -> set[int]:
    configured = {
        int(day) for day in (habit.schedule_days or [])
        if str(day).isdigit() and 1 <= int(day) <= 7
    }
    return configured or set(range(1, 8))


def scan_streaks(
    done: set[dt.date],
    start: dt.date,
    end: dt.date,
    grace: int,
    weekdays: set[int] | None = None,
) -> tuple[int, int]:
    """Chronological scan returning (current_trailing_streak, best_streak)."""
    current = best = 0
    skips: deque[dt.date] = deque()
    last_was_skip = False

    day = start
    while day <= end:
        if weekdays is not None and day.isoweekday() not in weekdays:
            day += DAY
            continue
        if day in done:
            current += 1
            best = max(best, current)
            last_was_skip = False
        else:
            while skips and skips[0] < day - dt.timedelta(days=6):
                skips.popleft()
            forgivable = (
                grace > 0 and len(skips) < grace and not last_was_skip and current > 0
            )
            if forgivable:
                # Grace-covered day: keeps the streak alive and counts toward it
                # (freeze-style), but consumes rolling-window budget.
                skips.append(day)
                last_was_skip = True
                current += 1
                best = max(best, current)
            else:
                current = 0
                skips.clear()
                last_was_skip = False
        day += DAY

    return current, best


def habit_streaks(habit: Habit, *, today: dt.date | None = None) -> dict[str, int]:
    """Computed streak stats for one habit."""
    today = today or _local_today()
    done = {log for log in habit.logs.filter(completed=True).values_list("date", flat=True)}
    start = _start_date(habit)
    # An unchecked *today* is pending, not broken.
    end = today if today in done else today - DAY
    if end < start:
        return {"current_streak": 0, "best_streak": 0}

    current, best = scan_streaks(
        done, start, end, habit.grace_days_per_week, scheduled_days(habit)
    )
    return {"current_streak": current, "best_streak": max(best, current)}


def completion_rate_30d(habit: Habit, *, today: dt.date | None = None) -> int:
    today = today or _local_today()
    start = max(today - dt.timedelta(days=29), _start_date(habit))
    days = sum(
        1
        for offset in range((today - start).days + 1)
        if (start + dt.timedelta(days=offset)).isoweekday()
        in scheduled_days(habit)
    )
    if days <= 0:
        return 0
    hits = habit.logs.filter(completed=True, date__gte=start, date__lte=today).count()
    return round(hits * 100 / days)


def heatmap(user, weeks: int = 26, *, today: dt.date | None = None) -> list[dict]:
    """GitHub-style consistency grid.

    ratio = completed / active-habits-that-day; level buckets 0..4 mirror
    the amber intensities in the UI design system.
    """
    today = today or _local_today()
    offset = today.weekday()  # Monday == 0
    grid_end = today
    grid_start = grid_end - dt.timedelta(days=(weeks - 1) * 7 + offset)

    habits = list(Habit.objects.filter(user=user, is_active=True))
    done_by_date: dict[dt.date, int] = {}
    if habits:
        rows = (
            HabitLog.objects.filter(
                habit__in=habits,
                completed=True,
                date__gte=grid_start,
                habit__created_at__lte=timezone.now(),
            )
            .values_list("date", flat=True)
        )
        for date in rows:
            done_by_date[date] = done_by_date.get(date, 0) + 1

    def level_for(ratio: float) -> int:
        if ratio <= 0:
            return 0
        if ratio <= 1 / 3:
            return 1
        if ratio <= 2 / 3:
            return 2
        if ratio < 1:
            return 3
        return 4

    out: list[dict] = []
    week_start = grid_start
    while week_start <= grid_end:
        days = []
        for i in range(7):
            day = week_start + dt.timedelta(days=i)
            if day > grid_end:
                break
            eligible = sum(
                1
                for h in habits
                if _start_date(h) <= day
                and day.isoweekday() in scheduled_days(h)
            )
            total = done_by_date.get(day, 0)
            ratio = round(total / eligible, 2) if eligible else 0
            days.append({"date": day.isoformat(), "ratio": ratio, "level": level_for(ratio)})
        out.append({"week_start": week_start.isoformat(), "days": days})
        week_start += dt.timedelta(days=7)
    return out
