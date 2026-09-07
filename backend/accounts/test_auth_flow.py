"""End-to-end JWT auth flow: register -> token -> refresh -> profile."""
import base64

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

PASSWORD = "Str0ng-Passphrase-42"


class JwtAuthFlowTests(APITestCase):
    def _register(self, username="walker"):
        return self.client.post(
            "/api/v1/auth/register/",
            {"username": username, "email": username + "@mura.app", "password": PASSWORD},
            format="json",
        )

    def test_register_returns_token_pair(self):
        """Contract: POST /auth/register/ -> {access, refresh}."""
        res = self._register()
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        body = res.json()
        self.assertIn("access", body)
        self.assertIn("refresh", body)

    def test_registered_user_can_reach_profile_with_access_token(self):
        tokens = self._register().json()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens["access"])
        res = self.client.get("/api/v1/me/")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.json()["username"], "walker")

    def test_token_obtain_and_refresh(self):
        self._register()
        res = self.client.post(
            "/api/v1/auth/token/", {"username": "walker", "password": PASSWORD}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        pair = res.json()
        self.assertIn("access", pair)
        self.assertIn("refresh", pair)

        refresh_res = self.client.post(
            "/api/v1/auth/token/refresh/", {"refresh": pair["refresh"]}, format="json"
        )
        self.assertEqual(refresh_res.status_code, status.HTTP_200_OK, refresh_res.content)
        new_access = refresh_res.json()["access"]

        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + new_access)
        self.assertEqual(self.client.get("/api/v1/me/").status_code, status.HTTP_200_OK)

    def test_token_obtain_rejects_bad_password(self):
        self._register()
        res = self.client.post(
            "/api/v1/auth/token/", {"username": "walker", "password": "wrong-pass"}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_requires_authentication(self):
        res = self.client.get("/api/v1/me/")
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_patch_display_name(self):
        tokens = self._register().json()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens["access"])
        res = self.client.patch("/api/v1/me/", {"display_name": "Discipline Walker"}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        self.assertEqual(res.json()["display_name"], "Discipline Walker")
        # Persisted across requests.
        got = self.client.get("/api/v1/me/").json()
        self.assertEqual(got["display_name"], "Discipline Walker")

    def test_authenticated_avatar_upload_and_delete(self):
        tokens = self._register().json()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens["access"])
        image = SimpleUploadedFile(
            "avatar.png",
            base64.b64decode(
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk"
                "+A8AAQUBAScY42YAAAAASUVORK5CYII="
            ),
            content_type="image/png",
        )
        uploaded = self.client.post(
            "/api/v1/me/avatar/", {"avatar": image}, format="multipart"
        )
        self.assertEqual(uploaded.status_code, status.HTTP_200_OK, uploaded.content)
        self.assertIn("/media/avatars/", uploaded.json()["avatar"])
        self.assertEqual(self.client.get("/api/v1/me/").json()["avatar"], uploaded.json()["avatar"])

        deleted = self.client.delete("/api/v1/me/avatar/")
        self.assertEqual(deleted.status_code, status.HTTP_200_OK)
        self.assertIsNone(deleted.json()["avatar"])

    def test_register_rejects_weak_password(self):
        res = self.client.post(
            "/api/v1/auth/register/",
            {"username": "weakling", "email": "w@mura.app", "password": "123"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", res.json())

    def test_register_rejects_duplicate_username(self):
        self._register()
        res = self._register()
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("username", res.json())

    def test_me_cannot_change_username_or_id(self):
        tokens = self._register().json()
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens["access"])
        res = self.client.patch("/api/v1/me/", {"username": "hijacked", "id": 99999}, format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        body = self.client.get("/api/v1/me/").json()
        self.assertEqual(body["username"], "walker")          # read-only field ignored
        self.assertNotEqual(body["id"], 99999)


class EmployeeRegistrationGateTests(APITestCase):
    """/auth/register/employee/ must be gated by EMPLOYEE_SIGNUP_KEY."""

    def _register_employee(self, signup_key=None):
        payload = {"username": "writer1", "email": "w@mura.app", "password": PASSWORD}
        if signup_key is not None:
            payload["signup_key"] = signup_key
        return self.client.post("/api/v1/auth/register/employee/", payload, format="json")

    def test_registration_disabled_without_configured_key(self):
        with self.settings(EMPLOYEE_SIGNUP_KEY=""):
            res = self._register_employee()
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn("signup_key", res.json())
            from django.contrib.auth import get_user_model

            self.assertFalse(
                get_user_model().objects.filter(username="writer1").exists(),
                "no staff account may be created when the gate is unset",
            )

    def test_registration_rejects_wrong_key(self):
        with self.settings(EMPLOYEE_SIGNUP_KEY="correct-horse"):
            res = self._register_employee(signup_key="wrong")
            self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn("signup_key", res.json())

    def test_registration_with_correct_key_creates_staff(self):
        with self.settings(EMPLOYEE_SIGNUP_KEY="correct-horse"):
            res = self._register_employee(signup_key="correct-horse")
            self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
            from django.contrib.auth import get_user_model

            user = get_user_model().objects.get(username="writer1")
            self.assertTrue(user.is_staff)
            self.assertFalse(user.is_superuser)
