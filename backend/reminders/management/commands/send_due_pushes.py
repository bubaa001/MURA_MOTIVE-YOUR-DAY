"""Send campaigns that are due right now (daily morning / weekly day).

Run by a scheduled task every few minutes, e.g. every 5 minutes:

    python manage.py send_due_pushes

Campaigns are deduped per day via last_sent_date, so re-runs are safe.
Delivery is FCM-only (Google push) — see reminders/push_views.py.
"""
import datetime as dt

from django.core.management.base import BaseCommand
from django.utils import timezone

from reminders.models import PushCampaign
from reminders.push_views import deliver_campaign


class Command(BaseCommand):
    help = "Send due PushCampaign broadcasts via FCM (daily/weekly schedules)."

    def handle(self, *args, **options):
        now = timezone.localtime()
        today = now.date()
        weekday = now.weekday()
        current_time = now.time()

        due = []
        for c in PushCampaign.objects.filter(is_active=True):
            if c.last_sent_date == today:
                continue
            if c.schedule == "daily":
                if current_time >= c.send_time:
                    due.append(c)
            elif c.schedule == "weekly":
                if c.weekday == weekday and current_time >= c.send_time:
                    due.append(c)

        if not due:
            self.stdout.write("No campaigns due right now.")
            return

        for c in due:
            result = deliver_campaign(c)
            c.last_sent_date = today
            c.save(update_fields=("last_sent_date",))
            self.stdout.write(
                self.style.SUCCESS(f"sent: {c.title} -> {result.get('delivered', 0)} device(s)")
            )
