"""Reminders API: days-field validation and basic CRUD shape."""
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import User


def _payload(**overrides):
    base = {
        "title": "Morning run",
        "message": "Lace up.",
        "time": "06:30",
        "days": [0, 2, 4],
        "category": "health",
    }
    base.update(overrides)
    return {k: v for k, v in base.items() if v is not None}


class ReminderValidationTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="nudger", password="test-pass-123")
        self.client.force_authenticate(self.user)
        self.url = "/api/v1/reminders/"

    def _post(self, payload):
        return self.client.post(self.url, payload, format="json")

    def test_valid_days_accepted(self):
        res = self._post(_payload())
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        body = res.json()
        self.assertEqual(body["days"], [0, 2, 4])
        for key in ("id", "title", "message", "time", "days", "category", "is_active", "created_at"):
            self.assertIn(key, body)

    def test_days_out_of_range_rejected(self):
        res = self._post(_payload(days=[7]))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)

    def test_days_negative_rejected(self):
        res = self._post(_payload(days=[-1]))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_days_non_integer_entries_rejected(self):
        res = self._post(_payload(days=["x"]))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_days_mixed_valid_and_invalid_rejected(self):
        res = self._post(_payload(days=[0, "3", 6]))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_days_non_list_rejected(self):
        res = self._post(_payload(days="daily"))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_empty_days_means_daily(self):
        res = self._post(_payload(days=[]))
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.json()["days"], [])

    def test_days_default_when_omitted(self):
        res = self._post(_payload(days=None))
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        self.assertEqual(res.json()["days"], [])

    def test_patch_validates_days_too(self):
        created = self._post(_payload()).json()
        res = self.client.patch(
            f"{self.url}{created['id']}/", {"days": [7]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_category_rejected(self):
        res = self._post(_payload(category="chaos"))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_time_required(self):
        res = self._post(_payload(time=None))
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
