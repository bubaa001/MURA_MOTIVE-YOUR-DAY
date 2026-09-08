"""FCM HTTP v1 push sender (Firebase Cloud Messaging).

The mobile app registers FCM device tokens at /me/devices/; this module
delivers pushes through Google's OAuth-secured HTTP v1 API so they arrive
on every Android phone — no third-party app (like Signo) needs to be
installed on the user's device.

Configuration (backend .env, never committed — see .env.example):
    FCM_PROJECT_ID     Firebase project id
    FCM_CLIENT_EMAIL   the service account's email (ends in iam.gserviceaccount.com)
    FCM_PRIVATE_KEY    the service account's private key (PEM, with \n escapes)

Until those are set, send_fcm() returns None (push disabled) — same
best-effort contract as Signo, so no caller needs to change behaviour.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

import jwt
from django.conf import settings

logger = logging.getLogger(__name__)

# OAuth scope for the FCM HTTP v1 API.
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
TOKEN_URL = "https://oauth2.googleapis.com/token"
FCM_URL_TMPL = "https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"

# Cached OAuth access token: (token, expires_at_monotonic).
_access_cache: tuple[str, float] | None = None

# Errors signifying the token is dead; the row must be deactivated so we
# stop trying to reach an app that was uninstalled or logged out.
_UNREGISTERED_MARKERS = ("UNREGISTERED", "NotRegistered")


class FcmError(Exception):
    """Raised when FCM is configured but rejects or cannot receive a message."""


def fcm_configured() -> bool:
    return bool(
        getattr(settings, "FCM_PROJECT_ID", "")
        and getattr(settings, "FCM_CLIENT_EMAIL", "")
        and getattr(settings, "FCM_PRIVATE_KEY", "")
    )


def _service_account_access_token() -> str:
    """Mint (and cache) an OAuth2 access token from the service-account key.

    Signs a short-lived JWT with PyJWT's RS256 — the cryptography package
    (already a project dependency) supplies the RSA implementation.
    """
    global _access_cache
    now = time.time()
    if _access_cache and _access_cache[1] > now + 60:
        return _access_cache[0]

    private_key = settings.FCM_PRIVATE_KEY.replace("\\n", "\n")
    assertion = jwt.encode(
        {
            "iss": settings.FCM_CLIENT_EMAIL,
            "scope": FCM_SCOPE,
            "aud": TOKEN_URL,
            "iat": int(now),
            "exp": int(now) + 3600,
        },
        private_key,
        algorithm="RS256",
    )
    # The OAuth2 token endpoint requires form-encoded fields, not JSON.
    form = urllib.parse.urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        TOKEN_URL,
        data=form,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    token = data["access_token"]
    _access_cache = (token, now + float(data.get("expires_in", 3600)))
    return token


def send_fcm(
    device_token: str,
    title: str,
    body: str = "",
    *,
    payload: dict[str, Any] | None = None,
    timeout: int = 10,
) -> dict[str, Any] | None:
    """Push to one device. Returns None when FCM is unconfigured.

    Raises [FcmError] on any send failure so the caller can decide whether
    the token should be deactivated; never fails silently *and* never
    blocks the caller — the shared notify_user() wrapper owns try/except.
    """
    if not fcm_configured():
        return None

    message: dict[str, Any] = {
        "token": device_token,
        "notification": {"title": title[:120], "body": (body or "")[:500]},
    }
    if payload:
        message["data"] = {k: str(v) for k, v in payload.items()}

    req = urllib.request.Request(
        FCM_URL_TMPL.format(project_id=settings.FCM_PROJECT_ID),
        data=json.dumps({"message": message}).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {_service_account_access_token()}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise FcmError(f"HTTP {exc.code}: {detail[:300]}") from exc
    except Exception as exc:  # network / parse failures
        raise FcmError(str(exc)) from exc


def is_unregistered(error: FcmError | str) -> bool:
    """True when FCM told us this exact token no longer exists."""
    text = str(error)
    return any(marker in text for marker in _UNREGISTERED_MARKERS)
