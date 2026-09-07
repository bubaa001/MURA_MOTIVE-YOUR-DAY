"""Dump the production database to a timestamped JSON file inside the repo.

Safe by design:
* read-only against the live DB (Django dumpdata),
* never overwrites or deletes anything,
* one file per run, named with the UTC timestamp.

Run it from cron/Task Scheduler on the PythonAnywhere box and copy the
backups off-box (see docs/runbook.md). Restore with:
    python manage.py loaddata backups/mura-YYYYMMDD-HHMMSS.json
"""
from __future__ import annotations

import os
from datetime import datetime, timezone as dt_timezone

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError

BACKUP_DIR = "backups"


class Command(BaseCommand):
    help = "Export all app data to a timestamped JSON fixture (read-only, never destructive)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--keep",
            type=int,
            default=30,
            help="Retain only the N newest backups (0 keeps everything). Default 30.",
        )

    def handle(self, *args, **options):
        os.makedirs(BACKUP_DIR, exist_ok=True)
        stamp = datetime.now(dt_timezone.utc).strftime("%Y%m%d-%H%M%S")
        path = os.path.join(BACKUP_DIR, f"mura-{stamp}.json")

        with open(path, "w", encoding="utf-8") as fh:
            call_command("dumpdata", "--exclude=contenttypes", "--exclude=sessions",
                         "--exclude=admin", indent=2, stdout=fh)

        size_kb = os.path.getsize(path) // 1024
        self.stdout.write(self.style.SUCCESS(f"Backup written: {path} ({size_kb} KB)"))

        keep = options["keep"]
        if keep > 0:
            backups = sorted(
                f for f in os.listdir(BACKUP_DIR)
                if f.startswith("mura-") and f.endswith(".json")
            )
            for stale in backups[:-keep]:
                os.remove(os.path.join(BACKUP_DIR, stale))
                self.stdout.write(f"Pruned old backup: {stale}")

        if size_kb > 50_000:
            self.stdout.write(self.style.WARNING(
                "Backup is large — the 512 MB free-tier disk fills fast. "
                "Copy backups off-box (see docs/runbook.md)."
            ))
