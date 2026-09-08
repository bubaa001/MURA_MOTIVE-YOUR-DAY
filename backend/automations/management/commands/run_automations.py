"""Fire time-based automation rules (daily_nudge).

Designed for the PythonAnywhere hourly scheduled task, exactly like
push_due_reminders: a rule is due when its HH:MM has passed today (within
a 2h catch-up window), it is active, and it has not fired today
(last_fired_date dedupes re-runs). Rules with only_if_incomplete=true
hold their fire while today's habit checklist still has open items.

    python manage.py run_automations [--dry-run]
"""

from __future__ import annotations

import datetime as dt

from django.core.management.base import BaseCommand
from django.utils import timezone

from automations.engine import day_complete
from automations.models import AutomationRule

# How late a run may be and still fire the rule it missed; must cover the
# scheduler gap plus clock skew (2h catches one skipped hourly run).
CATCHUP_WINDOW = dt.timedelta(hours=2)


class Command(BaseCommand):
    help = "Fire due daily_nudge automation rules (push + in-app notification)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="List what would fire without sending.",
        )

    def handle(self, *args, **options) -> None:
        now = timezone.localtime()
        today = now.date()
        window_start = (now - CATCHUP_WINDOW).time()
        current_time = now.time().replace(second=0, microsecond=0)

        due = []
        yesterday = today - dt.timedelta(days=1)
        # The 2h window crosses midnight when now is shortly after 00:00.
        wrapped = window_start > current_time
        for rule in AutomationRule.objects.filter(is_active=True, trigger_type="daily_nudge"):
            cfg = rule.trigger_config or {}
            try:
                fire_at = dt.time.fromisoformat(str(cfg.get("time")))
            except (TypeError, ValueError):
                self.stderr.write(f"SKIPPED (bad time): {rule.name} (user={rule.user_id})")
                continue
            # fire_at at/before now = today's slot (dedup on today);
            # fire_at after now (only reachable when wrapped) =
            # yesterday's missed slot (dedup on yesterday so a slot that
            # already fired never double-sends after midnight).
            in_window: bool
            already_fired_on: dt.date
            if fire_at <= current_time:
                # Wrapped window always covers [00:00 .. now].
                in_window = wrapped or fire_at >= window_start
                already_fired_on = today
            else:
                in_window = wrapped and fire_at >= window_start
                already_fired_on = yesterday
            if in_window and rule.last_fired_date != already_fired_on:
                due.append((rule, fire_at))

        if not due:
            self.stdout.write("no automations due")
            return

        sent = held = failed = 0
        for rule, fire_at in due:
            label = f"{rule.name} (user={rule.user_id}, {fire_at:%H:%M})"
            cfg = rule.trigger_config or {}
            if cfg.get("only_if_incomplete"):
                try:
                    incomplete = not day_complete(rule.user)
                except Exception as exc:
                    failed += 1
                    self.stderr.write(f"FAILED: {label}: {exc}")
                    continue
                if incomplete:
                    held += 1
                    self.stdout.write(f"held (habits incomplete): {label}")
                    continue
            if options["dry_run"]:
                self.stdout.write(f"would fire: {label}")
                continue
            try:
                from automations.engine import _fire

                _fire(rule)
                sent += 1
                self.stdout.write(f"fired: {label}")
            except Exception as exc:
                failed += 1
                self.stderr.write(f"FAILED: {label}: {exc}")

        self.stdout.write(self.style.SUCCESS(f"sent={sent} held={held} failed={failed}"))
