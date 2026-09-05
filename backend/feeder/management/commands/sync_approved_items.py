"""Push approved, unsynced ExtractedItems into the main app's ContentItem hub.

Same engine as the dashboard's "Sync approved" button — handy for cron or when
working from the terminal:

    python manage.py sync_approved_items
"""
from django.core.management.base import BaseCommand

from feeder.models import ExtractedItem
from feeder.services import sync_items


class Command(BaseCommand):
    help = "Sync approved, unsynced feeder items into ContentItem."

    def handle(self, *args, **options):
        targets = list(ExtractedItem.objects.filter(review_status="approved", synced=False))
        if not targets:
            self.stdout.write("Nothing to sync.")
            return
        synced = sync_items(targets)
        self.stdout.write(self.style.SUCCESS(f"Submitted {len(targets)} approved item(s); {synced} newly created in ContentItem."))
