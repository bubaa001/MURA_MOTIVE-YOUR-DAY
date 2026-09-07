"""TheFeeder review queue + sync tests (book extraction was erased)."""
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from content.models import ContentItem

from .models import ExtractedItem
from .services import sync_items


class FeederApiTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        from django.contrib.auth import get_user_model

        cls.user = get_user_model().objects.create_user(
            username="buba", password="secret-pass-123", is_staff=True
        )

    def setUp(self):
        self.client.force_authenticate(self.user)

    @staticmethod
    def make_superuser():
        from django.contrib.auth import get_user_model

        return get_user_model().objects.create_user(
            username="owner", password="secret-pass-123", is_staff=True, is_superuser=True
        )

    def test_requires_staff(self):
        from django.contrib.auth import get_user_model

        self.client.force_authenticate(
            get_user_model().objects.create_user(username="pleb", password="secret-pass-123")
        )
        self.assertEqual(self.client.get("/api/v1/feeder/items/").status_code, 403)
        self.assertEqual(self.client.get("/api/v1/feeder/content/").status_code, 403)

    def test_sync_requires_superuser(self):
        # Staff must NOT be able to force content live (publish gate).
        res = self.client.post(reverse("feeder-item-sync"))
        self.assertEqual(res.status_code, 403)
        item = ExtractedItem.objects.create(
            type="quote", text="staff cannot publish", source="s", review_status="approved"
        )
        res = self.client.post(reverse("feeder-item-sync-item", args=[item.id]))
        self.assertEqual(res.status_code, 403)
        self.assertFalse(ContentItem.objects.filter(text="staff cannot publish").exists())

    def test_manual_submit_enters_pending_review_queue(self):
        url = reverse("feeder-item-manual-submit")
        res = self.client.post(
            url,
            {
                "type": "spiritual_insight",
                "text": "Peace grows when we make room for stillness.",
                "source": "Community member",
                "tags": ["Peace", "stillness", "peace"],
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        item = ExtractedItem.objects.get(pk=res.data["item"]["id"])
        self.assertEqual(item.review_status, "pending")
        self.assertEqual(item.tags, ["peace", "stillness"])
        self.assertFalse(ContentItem.objects.filter(text=item.text).exists())

    def test_list_filters_by_status_and_type(self):
        ExtractedItem.objects.create(type="quote", text="q1", source="s", review_status="pending")
        ExtractedItem.objects.create(type="quote", text="q2", source="s", review_status="approved")
        res = self.client.get("/api/v1/feeder/items/?review_status=pending")
        self.assertEqual(len(res.json()["results"]), 1)
        res = self.client.get("/api/v1/feeder/items/?type=quote")
        self.assertEqual(len(res.json()["results"]), 2)

    def test_bulk_review_updates_items(self):
        a = ExtractedItem.objects.create(type="quote", text="t1", source="s")
        b = ExtractedItem.objects.create(type="quote", text="t2", source="s")
        res = self.client.post(
            reverse("feeder-item-bulk-review"),
            {"ids": [a.id, b.id], "review_status": "approved"},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["updated"], 2)
        self.assertEqual(
            ExtractedItem.objects.filter(review_status="approved").count(), 2
        )

    def test_delete_candidate(self):
        item = ExtractedItem.objects.create(type="quote", text="doomed", source="s")
        res = self.client.delete(f"/api/v1/feeder/items/{item.id}/")
        self.assertEqual(res.status_code, 204)
        self.assertFalse(ExtractedItem.objects.filter(pk=item.pk).exists())

    def test_sync_pushes_approved_items_and_dedupes(self):
        ExtractedItem.objects.create(
            type="quote", text="Already there.", source="Book A", tags=["x"],
            review_status="approved",
        )
        ContentItem.objects.create(type="quote", text="Already there.", source="seeded")
        self.client.force_authenticate(self.make_superuser())
        res = self.client.post(reverse("feeder-item-sync"))
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["submitted"], 1)
        self.assertEqual(res.data["synced"], 0)  # duplicate skipped but marked synced
        self.assertEqual(ContentItem.objects.filter(text="Already there.").count(), 1)
        item = ExtractedItem.objects.get(review_status="approved")
        self.assertTrue(item.synced)

    def test_sync_publishes_and_records_provenance(self):
        item = ExtractedItem.objects.create(
            type="journal_story", text="A brand new story", source="Buba", review_status="approved"
        )
        self.client.force_authenticate(self.make_superuser())
        res = self.client.post(reverse("feeder-item-sync"))
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["synced"], 1)
        live = ContentItem.objects.get(type="journal_story", text="A brand new story")
        self.assertEqual(live.status, "published")
        self.assertEqual(live.feeder_item_id, item.id)


class SyncItemsUnitTests(APITestCase):
    def test_sync_items_marks_synced_and_copies_image(self):
        from django.core.files.base import ContentFile

        candidate = ExtractedItem.objects.create(
            type="quote",
            text="Do it.",
            source="Me",
            tags=["action"],
            review_status="approved",
        )
        candidate.image.save("q.png", ContentFile(b"not-a-real-image"), save=False)
        candidate.save(update_fields=["image"])

        report = sync_items([candidate])
        self.assertEqual(report[candidate.id], {"content_id": 1, "created": True, "ok": True})
        item = ContentItem.objects.get(type="quote", text="Do it.")
        self.assertEqual(item.status, "published")
        self.assertEqual(item.feeder_item_id, candidate.id)
        candidate.refresh_from_db()
        self.assertTrue(candidate.synced)

    def test_sync_is_idempotent(self):
        candidate = ExtractedItem.objects.create(
            type="quote", text="Once.", source="Me", review_status="approved"
        )
        first = sync_items([candidate])
        self.assertEqual(first[candidate.id]["created"], True)
        second = sync_items([candidate])  # duplicate -> no new item
        self.assertEqual(second[candidate.id]["created"], False)
        self.assertTrue(second[candidate.id]["ok"])
        self.assertEqual(ContentItem.objects.filter(type="quote", text="Once.").count(), 1)
