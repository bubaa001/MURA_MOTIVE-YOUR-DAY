"""Unified notification helper.

Every user-facing push goes through notify_user(): Google's Firebase
Cloud Messaging (FCM) to each of the user's active device tokens. FCM
reaches every Android phone with the app installed — no third-party app
required. If the account has no registered device (or all sends fail),
the push is simply not delivered — the in-app notification feed written
by callers is the guaranteed-delivery channel.
"""

from __future__ import annotations

import logging
from typing import Any

from accounts.models import DeviceToken
from push import FcmError, fcm_configured, is_unregistered, send_fcm

logger = logging.getLogger(__name__)


def notify_user(
    user,
    title: str,
    body: str = "",
    *,
    priority: str = "default",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Best-effort FCM push to one user; NEVER raises.

    Returns a summary dict {"channel": "fcm"|"none", "devices": n} so
    scheduled commands can log what they did.
    """
    if not fcm_configured():
        return {"channel": "none", "devices": 0}
    devices = list(
        DeviceToken.objects.filter(user=user, is_active=True).values_list(
            "token", flat=True
        )
    )
    if not devices:
        return {"channel": "none", "devices": 0}

    delivered = 0
    for token in devices:
        try:
            send_fcm(token, title, body, payload=payload)
            delivered += 1
        except FcmError as exc:
            if is_unregistered(exc):
                # App uninstalled or logged out — stop targeting it.
                DeviceToken.objects.filter(token=token).update(is_active=False)
                logger.info("deactivated dead FCM token %s…", token[:12])
            else:
                logger.warning("FCM push to %s… failed: %s", token[:12], exc)
    return {"channel": "fcm" if delivered else "none", "devices": delivered}
