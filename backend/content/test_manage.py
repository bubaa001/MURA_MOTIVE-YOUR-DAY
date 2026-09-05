"""TheFeeder studio: published filtering + full content management API tests."""
import base64

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from accounts.models import User
from .models import ContentItem


_REAL_PNG = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)


def _png():
    return SimpleUploadedFile(
        "art.png", base64.b64decode(_REAL_PNG), content_type="image/png"
    )


class PublishedFilteringTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.user = User.objects.create_user(username="reader", password="test-pass-123")
        cls.published = ContentItem.objects.create(type="journal_story", text="Visible story", source="Me")
        cls.draft = ContentItem.objects.create(type="journal_story", text="Hidden draft", status="draft")
        cls.archived = ContentItem.objects.create(type="quote", text="Hidden archived", status="archived")
        cls.motion_pub = ContentItem.objects.create(type="motion_quote", text="Go.", status="published")
        cls.motion_draft = ContentItem.objects.create(type="motion_quote", text="Later.", status="draft")

    def test_list_hides_non_published(self):
        self.client.force_authenticate(self.user)
        res = self.client.get("/api/v1/content/items/")
        self.assertEqual(res.status_code, 200)
        ids = {row["id"] for row in res.json()["results"]}
        self.assertIn(self.published.id, ids)
        self.assertNotIn(self.draft.id, ids)
        self.assertNotIn(self.archived.id, ids)

    def test_daily_feed_hides_non_published(self):
        self.client.force_authenticate(self.user)
        res = self.client.get("/api/v1/content/daily/")
        self.assertEqual(res.status_code, 200)
        quote = res.json()["quote"]
        self.assertIsNone(quote)  # archived quote must not appear

    def test_motion_feed_hides_non_published(self):
        self.client.force_authenticate(self.user)
        res = self.client.get("/api/v1/content/motion/")
        items = res.json()["items"]
        ids = {row["id"] for row in items}
        self.assertIn(self.motion_pub.id, ids)
        self.assertNotIn(self.motion_draft.id, ids)


class ContentManageApiTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.owner = User.objects.create_superuser(username="buba", password="test-pass-123", email="buba@mura.local")
        cls.staff = User.objects.create_user(username="editor", password="test-pass-123", is_staff=True)
        cls.plain = User.objects.create_user(username="reader", password="test-pass-123")
        cls.item = ContentItem.objects.create(
            type="journal_story", text="A synced story", source="Old Book",
            tags=["reflection"], status="published",
        )

    def _auth(self, user):
        self.client.force_authenticate(user)

    # --- Access control ------------------------------------------------------
    def test_anonymous_denied(self):
        res = self.client.get("/api/v1/feeder/content/")
        self.assertEqual(res.status_code, 401)

    def test_plain_user_denied(self):
        self._auth(self.plain)
        res = self.client.get("/api/v1/feeder/content/")
        self.assertEqual(res.status_code, 403)

    def test_staff_allowed(self):
        self._auth(self.staff)
        res = self.client.get("/api/v1/feeder/content/")
        self.assertEqual(res.status_code, 200)

    # --- List / filter / search ---------------------------------------------
    def test_list_all_statuses_with_filters(self):
        ContentItem.objects.create(type="quote", text="Draft line", status="draft")
        self._auth(self.staff)
        res = self.client.get("/api/v1/feeder/content/?status=archived")
        ids = {row["id"] for row in res.json()["results"]}
        self.assertEqual(ids, set())
        res = self.client.get("/api/v1/feeder/content/?type=journal_story&q=synced")
        ids = {row["id"] for row in res.json()["results"]}
        self.assertIn(self.item.id, ids)

    # --- Create & publish rules ---------------------------------------------
    def test_staff_create_forced_to_draft(self):
        self._auth(self.staff)
        res = self.client.post(
            "/api/v1/feeder/content/",
            {"type": "quote", "text": "New line", "status": "published"},
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.json()["status"], "draft")

    def test_owner_can_publish_instantly(self):
        self._auth(self.owner)
        res = self.client.post(
            "/api/v1/feeder/content/",
            {"type": "quote", "text": "Live line", "status": "published"},
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.json()["status"], "published")

    def test_staff_update_cannot_publish(self):
        self._auth(self.staff)
        item = ContentItem.objects.create(type="quote", text="Stays draft", status="draft")
        res = self.client.patch(
            f"/api/v1/feeder/content/{item.id}/",
            {"status": "published"},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        item.refresh_from_db()
        self.assertEqual(item.status, "draft")

    # --- Edit every field ----------------------------------------------------
    def test_edit_fields_and_image(self):
        self._auth(self.staff)
        res = self.client.patch(
            f"/api/v1/feeder/content/{self.item.id}/",
            {"text": "Edited text", "source": "New Source", "tags": ["edited"], "year": 2026},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.item.refresh_from_db()
        self.assertEqual(self.item.text, "Edited text")
        self.assertEqual(self.item.tags, ["edited"])

        res = self.client.patch(
            f"/api/v1/feeder/content/{self.item.id}/",
            {"image_file": _png()},
            format="multipart",
        )
        self.assertEqual(res.status_code, 200)
        self.item.refresh_from_db()
        self.assertIsNotNone(self.item.image)

        res = self.client.delete(f"/api/v1/feeder/content/{self.item.id}/image/")
        self.assertEqual(res.status_code, 200)
        self.item.refresh_from_db()
        # Django 6 returns an (empty) ImageFieldFile for a NULL column: falsy.
        self.assertFalse(self.item.image)

    # --- Lifecycle: archive / restore / delete -------------------------------
    def test_archive_hides_and_restore_needs_owner(self):
        self._auth(self.staff)
        res = self.client.post(
            "/api/v1/feeder/content/bulk/",
            {"ids": [self.item.id], "action": "archive"},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.item.refresh_from_db()
        self.assertEqual(self.item.status, "archived")

        # staff cannot restore (publish)
        res = self.client.post(
            "/api/v1/feeder/content/bulk/",
            {"ids": [self.item.id], "action": "restore"},
            format="json",
        )
        self.assertEqual(res.status_code, 403)

        self._auth(self.owner)
        res = self.client.post(
            "/api/v1/feeder/content/bulk/",
            {"ids": [self.item.id], "action": "restore"},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.item.refresh_from_db()
        self.assertEqual(self.item.status, "published")

    def test_hard_delete(self):
        self._auth(self.staff)
        victim = ContentItem.objects.create(type="quote", text="Doomed")
        res = self.client.delete(f"/api/v1/feeder/content/{victim.id}/")
        self.assertEqual(res.status_code, 204)
        self.assertFalse(ContentItem.objects.filter(pk=victim.pk).exists())

    def test_provenance_reported(self):
        from feeder.models import ExtractedItem

        candidate = ExtractedItem.objects.create(
            type="journal_story", text="T", source="Source Book", review_status="approved"
        )
        item = ContentItem.objects.create(type="journal_story", text="T", feeder_item=candidate)
        self._auth(self.staff)
        res = self.client.get(f"/api/v1/feeder/content/{item.id}/")
        prov = res.json()["provenance"]
        self.assertEqual(prov["feeder_item_id"], candidate.id)
        self.assertEqual(prov["book"], "Source Book")
