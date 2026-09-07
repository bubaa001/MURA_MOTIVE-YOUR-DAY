"""Push due reminders to each user's personal Signo topic.

Designed for PythonAnywhere scheduled tasks, which fire hourly at best:
a reminder is due when the current local time has PASSED its HH:MM today
(within a catch-up window so a task that runs at 09:05 still sends the
09:00 reminder), its weekday matches (Mon=0..Sun=6, empty days = every
day), it is active, and it has not already been pushed today
(last_pushed_date dedupes re-runs).

    python manage.py push_due_reminders
"""

from __future__ import annotations

import datetime as dt

from django.core.management.base import BaseCommand
from django.utils import timezone

from reminders.models import NotificationLog, Reminder
from reminders.signo import SignoError, send_user_event

# How late a run may be and still send the reminder it missed. Must cover
# the scheduler gap plus clock skew; 2h catches a skipped hourly run.
CATCHUP_WINDOW = dt.timedelta(hours=2)


class Command(BaseCommand):
    help = "Push reminders due right now to each user's personal topic via Signo."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="List what would be pushed without sending.",
        )

    def handle(self, *args, **options) -> None:
        now = timezone.localtime()
        today = now.date()
        weekday = now.weekday()  # Monday=0 .. Sunday=6, matches the app contract

        # Time-window match instead of exact HH:MM: a scheduler running
        # hourly (PythonAnywhere) or every few minutes still delivers.
        window_start = (now - CATCHUP_WINDOW).time()
        current_time = now.time().replace(second=0, microsecond=0)

        due = [
            r
            for r in Reminder.objects.filter(is_active=True, time__gte=window_start, time__lte=current_time)
            if (not r.days or weekday in r.days) and r.last_pushed_date != today
        ]
        if not due:
            self.stdout.write("no reminders due")
            return

        sent = failed = skipped = 0
        for reminder in due:
            label = f"{reminder.title} (user={reminder.user_id}, {reminder.time:%H:%M})"
            if options["dry_run"]:
                self.stdout.write(f"would push: {label}")
                continue
            try:
                result = send_user_event(
                    reminder.user,
                    title=reminder.title,
                    body=reminder.message,
                    priority="time-sensitive" if reminder.category in {"health", "mental"} else "default",
                    payload={"kind": "reminder", "reminderId": reminder.id, "category": reminder.category},
                )
            except SignoError as exc:
                failed += 1
                self.stderr.write(f"FAILED: {label}: {exc}")
                continue
            reminder.last_pushed_date = today
            reminder.save(update_fields=["last_pushed_date"])
            NotificationLog.objects.create(
                user=reminder.user,
                title=reminder.title,
                body=reminder.message,
                kind="reminder",
            )
            if result:
                sent += 1
                self.stdout.write(f"pushed: {label} -> {result.get('delivered')} device(s)")
            else:
                # Recorded in the in-app feed even though the user has no
                # personal push topic subscribed yet.
                skipped += 1
                self.stdout.write(f"logged only (no personal topic): {label}")

        self.stdout.write(self.style.SUCCESS(f"sent={sent} skipped={skipped} failed={failed}"))
