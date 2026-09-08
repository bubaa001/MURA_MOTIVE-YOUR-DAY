"""Publish an APK build for the in-app updater.

    python manage.py publish_release ^
        --apk C:/path/to/app-release.apk ^
        --version-name 1.1.0 --version-code 2 ^
        --notes "New Today screen + motion quotes"

With GitHub hosting (fast app downloads, no tunnel bottleneck):

    set GITHUB_TOKEN=ghp_xxx
    python manage.py publish_release --apk app-release.apk --version-name 1.2.0         --version-code 3 --github bubaa001/MURA_MOTIVE-YOUR-DAY

Idempotent per version_code.
"""
import json
import os
import urllib.parse
import urllib.request

from django.core.management.base import BaseCommand, CommandError

from updates.models import Release

API = "https://api.github.com"


def _gh(token: str, method: str, url: str, data=None, headers=None, binary=None):
    req_headers = {"Authorization": f"token {token}", "Accept": "application/vnd.github+json"}
    if headers:
        req_headers.update(headers)
    body = binary
    if data is not None and binary is None:
        body = json.dumps(data).encode("utf-8")
        req_headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=120) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:300]
        raise CommandError(f"GitHub {method} {url} -> {exc.code}: {detail}")


def upload_to_github(token: str, repo: str, apk_path: str, version_name: str) -> str:
    tag = f"v{version_name}"
    # ensure release exists (idempotent)
    try:
        release = _gh(token, "GET", f"{API}/repos/{repo}/releases/tags/{tag}")
    except CommandError:
        release = _gh(token, "POST", f"{API}/repos/{repo}/releases",
                      {"tag_name": tag, "name": tag, "body": f"MURA {version_name}"})
    asset_name = f"MURA-v{version_name}.apk"
    # delete prior asset with the same name so re-publish replaces it
    assets = _gh(token, "GET", f"{API}/repos/{repo}/releases/{release['id']}/assets")
    for asset in assets:
        if asset["name"] == asset_name:
            _gh(token, "DELETE", f"{API}/repos/{repo}/releases/assets/{asset['id']}")
    upload_url = release["upload_url"].split("{")[0]
    with open(apk_path, "rb") as fh:
        binary = fh.read()
    asset = _gh(token, "POST", f"{upload_url}?name={urllib.parse.quote(asset_name)}",
                headers={"Content-Type": "application/vnd.android.package-archive"}, binary=binary)
    return asset["browser_download_url"]


class Command(BaseCommand):
    help = "Publish an APK so installed apps are offered the update."

    def add_arguments(self, parser):
        parser.add_argument("--apk", default="", help="Path to app-release.apk (skipped with --from-url)")
        parser.add_argument("--version-name", required=True)
        parser.add_argument("--version-code", type=int, required=True)
        parser.add_argument("--notes", default="", help="Short changelog shown in the app.")
        parser.add_argument("--github", default=os.environ.get("MURA_GITHUB_REPO", ""),
                            help="owner/repo to host the APK as a Release asset (fast CDN downloads).")
        parser.add_argument("--from-url", default="",
                            help="Skip the upload: point the manifest at an already-hosted APK "
                                 "(e.g. the GitHub release asset committed/pushed earlier).")
        parser.add_argument("--announce", action="store_true",
                            help="Push an 'update available' notification to every active FCM device.")

    def handle(self, *args, **options):
        apk_path = options["apk"]
        from_url = options["from_url"]
        if not from_url and not os.path.exists(apk_path):
            raise CommandError(f"APK not found: {apk_path}")
        size_mb = (os.path.getsize(apk_path) / (1024 * 1024)) if not from_url else 0.0

        release, created = Release.objects.get_or_create(
            version_code=options["version_code"],
            defaults={"version_name": options["version_name"], "notes": options["notes"]},
        )
        if not created:
            release.version_name = options["version_name"]
            release.notes = options["notes"]

        if from_url:
            release.apk_url_override = from_url
            self.stdout.write(f"Using hosted APK: {from_url}")
        elif options["github"]:
            token = os.environ.get("GITHUB_TOKEN", "")
            if not token:
                raise CommandError("--github given but GITHUB_TOKEN env var is not set.")
            download_url = upload_to_github(token, options["github"], apk_path, options["version_name"])
            release.apk_url_override = download_url
            self.stdout.write(f"Hosted APK on GitHub: {download_url}")
        else:
            with open(apk_path, "rb") as fh:
                release.apk.save(f"mura-{options['version_name']}.apk", fh, save=False)
        release.save()

        announced = 0
        if options["announce"]:
            announced = self._announce(release)

        msg = (f"{'Published' if created else 'Updated'} v{release.version_name} "
               f"(code {release.version_code}, {size_mb:.1f} MB).")
        if options["announce"]:
            msg += f" Announced to {announced} device(s)."
        self.stdout.write(self.style.SUCCESS(msg))

    def _announce(self, release: Release) -> int:
        """Push 'update available' to every active device; returns delivered count."""
        from accounts.models import DeviceToken
        from push import FcmError, fcm_configured, is_unregistered, send_fcm

        if not fcm_configured():
            self.stdout.write(self.style.WARNING(
                "FCM_* env vars missing — announced in-app feed only."))
            return 0
        title = f"MURA {release.version_name} is out"
        body = (release.notes or "Tap to download the update.").strip()
        payload = {"kind": "update", "version_code": release.version_code}
        delivered = 0
        for token in DeviceToken.objects.filter(is_active=True).values_list("token", flat=True):
            try:
                send_fcm(token, title, body, payload=payload)
                delivered += 1
            except FcmError as exc:
                if is_unregistered(exc):
                    DeviceToken.objects.filter(token=token).update(is_active=False)
                else:
                    self.stdout.write(self.style.WARNING(
                        f"push failed for {token[:12]}…: {exc}"))
        return delivered
