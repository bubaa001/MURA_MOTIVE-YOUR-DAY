"""Device registration (/me/devices/) — FCM token upsert + scoping."""
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import DeviceToken, User


def _make_user(username="deviceowner"):
    return User.objects.create_user(username=username, password="test-pass-123")


class DeviceApiTests(APITestCase):
    def setUp(self):
        self.user = _make_user()
        self.client.force_authenticate(self.user)

    def test_register_returns_created_and_is_idempotent(self):
        payload = {"token": "fcm-token-abc123", "platform": "android"}
        res = self.client.post("/api/v1/me/devices/", payload, format="json")
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        # Re-registering the same token (app restart, reinstall) must not
        # duplicate the row.
        res2 = self.client.post("/api/v1/me/devices/", payload, format="json")
        self.assertEqual(res2.status_code, status.HTTP_201_CREATED, res2.content)
        self.assertEqual(DeviceToken.objects.filter(user=self.user).count(), 1)

    def test_reactivate_after_soft_delete(self):
        DeviceToken.objects.create(user=self.user, token="tok-1")
        row = DeviceToken.objects.get(token="tok-1")
        res = self.client.delete(f"/api/v1/me/devices/{row.id}/")
        self.assertEqual(res.status_code, status.HTTP_204_NO_CONTENT, res.content)
        self.assertFalse(DeviceToken.objects.get(token="tok-1").is_active)
        # Signing back in on the same device re-activates the row.
        self.client.post(
            "/api/v1/me/devices/", {"token": "tok-1", "platform": "android"}, format="json"
        )
        self.assertTrue(DeviceToken.objects.get(token="tok-1").is_active)

    def test_list_scopes_to_owner(self):
        other = _make_user("deviceother")
        DeviceToken.objects.create(user=other, token="tok-other")
        DeviceToken.objects.create(user=self.user, token="tok-mine")
        body = self.client.get("/api/v1/me/devices/").json()
        self.assertEqual([d["token"] for d in body["results"]], ["tok-mine"])

    def test_delete_cannot_touch_other_users_device(self):
        other = _make_user("devicestranger")
        foreign = DeviceToken.objects.create(user=other, token="tok-foreign")
        self.assertEqual(
            self.client.delete(f"/api/v1/me/devices/{foreign.id}/").status_code, 404
        )
        DeviceToken.objects.get(pk=foreign.pk)  # still exists
