"""/content/items/?tag= JSON-containment filter."""
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import User
from .models import ContentItem


class TagFilterTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.user = User.objects.create_user(username="librarian", password="test-pass-123")
        ContentItem.objects.create(
            type="quote", text="A about discipline", source="S", tags=["discipline", "focus"]
        )
        ContentItem.objects.create(
            type="quote", text="B about wealth", source="S", tags=["wealth"]
        )
        ContentItem.objects.create(
            type="philosophy", text="C discipline philosophy", source="MURA", tags=["discipline"]
        )

    def setUp(self):
        self.client.force_authenticate(self.user)

    def test_tag_filter_returns_only_matching_items(self):
        res = self.client.get("/api/v1/content/items/?tag=discipline")
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        texts = [r["text"] for r in res.json()["results"]]
        self.assertEqual(sorted(texts), ["A about discipline", "C discipline philosophy"])

    def test_tag_filter_combines_with_type(self):
        res = self.client.get("/api/v1/content/items/?tag=discipline&type=quote")
        texts = [r["text"] for r in res.json()["results"]]
        self.assertEqual(texts, ["A about discipline"])

    def test_tag_with_no_matches_is_empty(self):
        res = self.client.get("/api/v1/content/items/?tag=nonexistent-tag")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.json()["results"], [])

    def test_partial_tag_string_does_not_match(self):
        # Containment must match whole tag values, not substrings of them.
        ContentItem.objects.create(type="quote", text="D", source="S", tags=["self-discipline"])
        res = self.client.get("/api/v1/content/items/?tag=discipline")
        texts = [r["text"] for r in res.json()["results"]]
        self.assertNotIn("D", texts)
