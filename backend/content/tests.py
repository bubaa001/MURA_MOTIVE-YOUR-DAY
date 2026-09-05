import datetime as dt

from rest_framework.test import APITestCase

from accounts.models import User
from .management.commands.seed_content import PHILOSOPHIES, PRAYERS, QUOTES
from .models import ContentEngagement, ContentItem


class ContentApiTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.user = User.objects.create_user(username="reader", password="test-pass-123")
        for text, source, tags in QUOTES[:3]:
            ContentItem.objects.create(type="quote", text=text, source=source, tags=tags)
        for text, source, tags in PRAYERS[:2]:
            ContentItem.objects.create(type="prayer", text=text, source=source, tags=tags)

    def test_requires_auth(self):
        res = self.client.get("/api/v1/content/items/")
        self.assertEqual(res.status_code, 401)

    def test_filter_by_type(self):
        self.client.force_authenticate(self.user)
        res = self.client.get("/api/v1/content/items/?type=prayer")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(len(res.json()["results"]), 2)

    def test_daily_is_deterministic_per_day(self):
        self.client.force_authenticate(self.user)
        day = dt.date(2026, 2, 1)
        a = self.client.get(f"/api/v1/content/daily/?date={day}").json()
        b = self.client.get(f"/api/v1/content/daily/?date={day}").json()
        self.assertEqual(a["quote"]["id"], b["quote"]["id"])
        next_day = day + dt.timedelta(days=1)
        c = self.client.get(f"/api/v1/content/daily/?date={next_day}").json()
        # With 3 quotes the rotation must move on (mod arithmetic guarantees it).
        self.assertNotEqual(a["quote"]["id"], c["quote"]["id"])

    def test_seed_command_is_idempotent(self):
        from django.core.management import call_command

        call_command("seed_content", verbosity=0)
        first_count = ContentItem.objects.count()
        expected = len(QUOTES) + len(PRAYERS) + len(PHILOSOPHIES)
        self.assertGreaterEqual(first_count, expected)
        call_command("seed_content", verbosity=0)
        self.assertEqual(ContentItem.objects.count(), first_count)

    def test_story_engagement_and_rankings(self):
        self.client.force_authenticate(self.user)
        story = ContentItem.objects.create(
            type="journal_story", text="A story", source="Author"
        )
        self.assertEqual(
            self.client.post(f"/api/v1/content/items/{story.id}/view/").status_code,
            200,
        )
        self.assertEqual(
            self.client.post(f"/api/v1/content/items/{story.id}/read/").status_code,
            200,
        )
        liked = self.client.post(f"/api/v1/content/items/{story.id}/like/")
        self.assertTrue(liked.json()["liked"])
        payload = self.client.get(
            "/api/v1/content/items/?type=journal_story&sort=most_liked&status=read"
        ).json()
        self.assertEqual(payload["results"][0]["id"], story.id)
        engagement = ContentEngagement.objects.get(item=story, user=self.user)
        self.assertIsNotNone(engagement.viewed_at)
        self.assertIsNotNone(engagement.read_at)
