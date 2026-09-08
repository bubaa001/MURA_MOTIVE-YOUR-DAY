"""In-app updater manifest endpoint tests."""
import io
from unittest import mock

from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import call_command
from django.test import TestCase
from rest_framework.test import APITestCase

from accounts.models import DeviceToken, User
from push import FcmError
from .models import Release


class UpdateManifestTests(APITestCase):
    def test_manifest_404_when_no_release(self):
        res = self.client.get("/api/v1/update/")
        self.assertEqual(res.status_code, 404)

    def test_manifest_returns_newest_release_publicly(self):
        Release.objects.create(
            version_code=1,
            version_name="1.0.0",
            apk=SimpleUploadedFile("mura-1.0.0.apk", b"apk", content_type="application/vnd.android.package-archive"),
        )
        Release.objects.create(
            version_code=2,
            version_name="1.1.0",
            notes="Fixes",
            apk=SimpleUploadedFile("mura-1.1.0.apk", b"apk2", content_type="application/vnd.android.package-archive"),
        )
        # No auth required — the app checks before login state matters.
        res = self.client.get("/api/v1/update/")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["version_code"], 2)
        self.assertEqual(body["version_name"], "1.1.0")
        self.assertEqual(body["notes"], "Fixes")
        self.assertIn("/media/releases/", body["apk_url"])


class PublishReleaseTests(TestCase):
    """The --from-url / --announce flags used when shipping a build."""

    def _out(self) -> str:
        buf = io.StringIO()
        call_command("publish_release", "--from-url", "https://cdn.example/mura.apk",
                     "--version-name", "1.4.2", "--version-code", "12",
                     "--notes", "Push notifications", stdout=buf)
        return buf.getvalue()

    def test_from_url_sets_override_without_file(self):
        out = self._out()
        self.assertIn("Published v1.4.2", out)
        release = Release.objects.get(version_code=12)
        self.assertEqual(release.apk_url_override, "https://cdn.example/mura.apk")
        self.assertFalse(release.apk)  # nothing stored on the server

    def test_from_url_is_idempotent_per_version_code(self):
        self._out()
        self._out()
        self.assertEqual(Release.objects.filter(version_code=12).count(), 1)

    def test_announce_pushes_to_every_active_device(self):
        user = User.objects.create_user(username="u1", password="x")
        DeviceToken.objects.create(user=user, token="tok-good", platform="android")
        DeviceToken.objects.create(user=user, token="tok-dead", platform="android",
                                    is_active=False)

        with mock.patch("push.send_fcm") as send:
            buf = io.StringIO()
            call_command("publish_release", "--from-url", "https://cdn.example/mura.apk",
                         "--version-name", "1.4.2", "--version-code", "12",
                         "--notes", "Push notifications", "--announce", stdout=buf)
            out = buf.getvalue()

        self.assertIn("Announced to 1 device(s)", out)
        send.assert_called_once()
        args, kwargs = send.call_args
        self.assertEqual(args[0], "tok-good")  # dead token skipped
        self.assertIn("1.4.2", args[1])
        self.assertEqual(kwargs["payload"]["kind"], "update")

    def test_announce_deactivates_unregistered_token(self):
        user = User.objects.create_user(username="u1", password="x")
        DeviceToken.objects.create(user=user, token="tok-old", platform="android")

        with mock.patch("push.send_fcm",
                        side_effect=FcmError("404: UNREGISTERED")):
            self._announce_only()

        self.assertFalse(DeviceToken.objects.get(token="tok-old").is_active)

    def test_announce_without_fcm_config_warns_not_crashes(self):
        with mock.patch("push.fcm_configured", return_value=False):
            buf = io.StringIO()
            call_command("publish_release", "--from-url", "https://cdn.example/mura.apk",
                         "--version-name", "1.4.2", "--version-code", "12",
                         "--notes", "n", "--announce", stdout=buf)
        self.assertIn("in-app feed only", buf.getvalue())

    def _announce_only(self):
        with mock.patch("push.fcm_configured", return_value=True):
            buf = io.StringIO()
            call_command("publish_release", "--from-url", "https://cdn.example/mura.apk",
                         "--version-name", "1.4.2", "--version-code", "12",
                         "--notes", "n", "--announce", stdout=buf)
