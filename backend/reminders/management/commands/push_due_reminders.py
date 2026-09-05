"""Push due reminders to every subscribed device via Signo.

Designed to run every minute (Task Scheduler / cron):

    python manage.py push_due_reminders

A reminder is due when its HH:MM equals the current local time, its weekday
matches (Mon=0..Sun=6, empty days = every day), it is active, and it has not
already been pushed today (last_pushed_date dedupes re-runs in the same
minute).
"""

from __future__ import annotations

import datetime as dt

from django.core.management.base import BaseCommand
from django.utils import timezone

from reminders.models import NotificationLog, Reminder
from reminders.signo import SignoError, send_event


class Command(BaseCommand):
    help = "Push reminders due right now to subscribed devices via Signo."

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

        due = [
            r
            for r in Reminder.objects.filter(is_active=True, time=now.time().replace(second=0, microsecond=0))
            if (not r.days or weekday in r.days) and r.last_pushed_date != today
        ]
        if not due:
            self.stdout.write("no reminders due")
            return

        sent = failed = 0
        for reminder in due:
            label = f"{reminder.title} (user={reminder.user_id}, {reminder.time:%H:%M})"
            if options["dry_run"]:
                self.stdout.write(f"would push: {label}")
                continue
            try:
                result = send_event(
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
            sent += 1
            self.stdout.write(f"pushed: {label} -> {result.get('delivered')} device(s)")

        self.stdout.write(self.style.SUCCESS(f"sent={sent} failed={failed}"))
