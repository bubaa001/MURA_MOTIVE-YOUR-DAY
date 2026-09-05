"""Publish an APK build for the in-app updater.

    python manage.py publish_release ^
        --apk C:/path/to/app-release.apk ^
        --version-name 1.1.0 --version-code 2 ^
        --notes "New Today screen + motion quotes"

Idempotent per version_code: re-publishing the same version replaces the APK.
"""
import os

from django.core.management.base import BaseCommand, CommandError

from updates.models import Release


class Command(BaseCommand):
    help = "Publish an APK so installed apps are offered the update."

    def add_arguments(self, parser):
        parser.add_argument("--apk", required=True, help="Path to app-release.apk")
        parser.add_argument("--version-name", required=True)
        parser.add_argument("--version-code", type=int, required=True)
        parser.add_argument("--notes", default="", help="Short changelog shown in the app.")

    def handle(self, *args, **options):
        apk_path = options["apk"]
        if not os.path.exists(apk_path):
            raise CommandError(f"APK not found: {apk_path}")
        size_mb = os.path.getsize(apk_path) / (1024 * 1024)

        release, created = Release.objects.get_or_create(
            version_code=options["version_code"],
            defaults={"version_name": options["version_name"], "notes": options["notes"]},
        )
        if not created:
            release.version_name = options["version_name"]
            release.notes = options["notes"]
        with open(apk_path, "rb") as fh:
            release.apk.save(f"mura-{options['version_name']}.apk", fh, save=False)
        release.save()

        self.stdout.write(
            self.style.SUCCESS(
                f"{'Published' if created else 'Updated'} v{release.version_name} "
                f"(code {release.version_code}, {size_mb:.1f} MB)."
            )
        )
