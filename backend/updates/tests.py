"""In-app updater manifest endpoint tests."""
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

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
