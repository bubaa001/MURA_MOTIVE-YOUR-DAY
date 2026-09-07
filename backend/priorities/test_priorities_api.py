"""Priorities API: ordering, reorder endpoint + its validation."""
import datetime as dt

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import User
from .models import Priority


class PriorityApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="prioritizer", password="test-pass-123")
        self.client.force_authenticate(self.user)
        self.ids = []
        for title in ("First", "Second", "Third"):
            res = self.client.post("/api/v1/priorities/", {"title": title}, format="json")
            self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
            self.ids.append(res.json()["id"])

    def _list(self, query=""):
        return self.client.get("/api/v1/priorities/" + query).json()["results"]

    def test_create_assigns_incrementing_order_and_today(self):
        results = self._list()
        self.assertEqual([r["order"] for r in results], [0, 1, 2])
        self.assertEqual(results[0]["date"], timezone.localdate().isoformat())

    def test_reorder_happy_path(self):
        res = self.client.post(
            "/api/v1/priorities/reorder/", {"ordered_ids": [self.ids[2], self.ids[0]]},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        self.assertEqual(res.json(), {"reordered": 2})
        titles = [r["title"] for r in self._list()]
        self.assertEqual(titles[:2], ["Third", "First"])

    def test_reorder_unknown_id_returns_400(self):
        res = self.client.post(
            "/api/v1/priorities/reorder/",
            {"ordered_ids": [self.ids[0], 99999]},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)
        # Nothing was reordered.
        titles = [r["title"] for r in self._list()]
        self.assertEqual(titles, ["First", "Second", "Third"])

    def test_reorder_empty_list_returns_400(self):
        res = self.client.post("/api/v1/priorities/reorder/", {"ordered_ids": []}, format="json")
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_reorder_non_integer_ids_return_400(self):
        res = self.client.post(
            "/api/v1/priorities/reorder/", {"ordered_ids": ["x"]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_reorder_missing_body_field_returns_400(self):
        res = self.client.post("/api/v1/priorities/reorder/", {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_toggle_completion_via_patch(self):
        pid = self.ids[0]
        res = self.client.patch(f"/api/v1/priorities/{pid}/", {"completed": True}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertTrue(res.json()["completed"])
        # order is read-only: PATCH must not clobber it.
        self.assertEqual(res.json()["order"], 0)

    def test_date_filter_scopes_list(self):
        import datetime as dt
        old = Priority.objects.create(user=self.user, title="Old", date=dt.date(2026, 1, 1))
        res = self.client.get("/api/v1/priorities/?date=2026-01-01").json()["results"]
        self.assertEqual([r["id"] for r in res], [old.id])
