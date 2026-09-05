"""Journal entries (search, ordering) and memories (date required)."""
import datetime as dt

from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import User


class JournalApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="diarist", password="test-pass-123")
        self.client.force_authenticate(self.user)
        self.url = "/api/v1/journal/entries/"
        res = self.client.post(
            self.url,
            {"title": "Cold plunge", "body": "Braved the ice bath this morning.", "mood": "great"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        self.first_id = res.json()["id"]
        second = self.client.post(
            self.url,
            {"title": "Deep work block", "body": "Three hours, no phone, no excuses.", "mood": "good"},
            format="json",
        )
        self.second_id = second.json()["id"]

    def test_list_newest_first_and_shape(self):
        body = self.client.get(self.url).json()
        results = body["results"]
        self.assertEqual(len(results), 2)
        self.assertEqual([r["id"] for r in results], [self.second_id, self.first_id])
        for entry in results:
            self.assertEqual(
                set(entry.keys()), {"id", "title", "body", "mood", "created_at", "updated_at"}
            )

    def test_search_matches_title_only_entries(self):
        results = self.client.get(self.url + "?search=plunge").json()["results"]
        self.assertEqual([r["title"] for r in results], ["Cold plunge"])

    def test_search_matches_body(self):
        titles = [
            r["title"]
            for r in self.client.get(self.url + "?search=phone").json()["results"]
        ]
        self.assertEqual(titles, ["Deep work block"])

    def test_search_no_hits(self):
        results = self.client.get(self.url + "?search=zebra").json()["results"]
        self.assertEqual(results, [])

    def test_mood_validation(self):
        res = self.client.post(
            self.url, {"title": "x", "body": "y", "mood": "ecstatic"}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)


class MemoryApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="collector", password="test-pass-123")
        self.client.force_authenticate(self.user)
        self.url = "/api/v1/memories/"

    def test_date_required(self):
        res = self.client.post(
            self.url, {"title": "First 10k", "description": "Under 50 minutes."}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)
        self.assertIn("date", res.json())

    def test_create_with_date(self):
        res = self.client.post(
            self.url,
            {"title": "First 10k", "description": "Under 50 minutes.", "date": "2026-02-01"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        body = res.json()
        self.assertEqual(body["date"], "2026-01-31" if False else "2026-02-01")  # echoed verbatim
        self.assertIsNone(body["photo"])

    def test_invalid_date_rejected(self):
        res = self.client.post(
            self.url, {"title": "x", "date": "02/01/2026"}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_list_shape_and_ordering_newest_date_first(self):
        self.client.post(
            self.url, {"title": "Old win", "date": dt.date(2025, 5, 1)}, format="json"
        )
        self.client.post(
            self.url, {"title": "New win", "date": dt.date(2026, 1, 15)}, format="json"
        )
        results = self.client.get(self.url).json()["results"]
        self.assertEqual([r["title"] for r in results], ["New win", "Old win"])
