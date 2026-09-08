"""Unified notification helper.

Every user-facing push goes through notify_user():
  1. FCM to each active device token (works on every Android phone —
     the user does not need any third-party app installed).
  2. If the account has NO active device, fall back to the legacy Signo
     personal topic (early adopters who installed Signo keep receiving
     pushes until the app update registers their device).
The in-app notification feed (NotificationLog) is written by callers
separately, as before — it is the guaranteed-delivery channel.
"""

from __future__ import annotations

import logging
from typing import Any

from accounts.models import DeviceToken
from push import FcmError, fcm_configured, is_unregistered, send_fcm
from reminders.signo import SignoError, send_user_event

logger = logging.getLogger(__name__)


def notify_user(
    user,
    title: str,
    body: str = "",
    *,
    priority: str = "default",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Best-effort push to one user; NEVER raises.

    Returns a summary dict {"channel": "fcm"|"signo"|"none", "devices": n}
    so scheduled commands can log what they did. A Signo fallback only
    happens when the user has no active FCM device — pushing to both would
    double-notify people who installed Signo.
    """
    devices = []
    if fcm_configured():
        devices = list(
            DeviceToken.objects.filter(user=user, is_active=True).values_list(
                "token", flat=True
            )
        )

    if devices:
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
        return {"channel": "fcm", "devices": delivered}

    try:
        result = send_user_event(user, title, body, priority=priority, payload=payload)
    except SignoError as exc:
        logger.warning("Signo push failed: %s", exc)
        return {"channel": "none", "devices": 0}
    if result is None:
        return {"channel": "none", "devices": 0}
    return {"channel": "signo", "devices": result.get("delivered", 0)}
