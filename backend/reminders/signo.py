"""Signo push client (https://signo.digitospace.com).

Signo delivers events to every device subscribed to a topic. The topic's
unguessable namespace is the address — no auth header required. The namespace
comes from SIGNO_NAMESPACE in the environment (see .env.example).
"""

from __future__ import annotations

import json
import logging
import urllib.request
from typing import Any

from django.conf import settings

logger = logging.getLogger(__name__)

SIGNO_URL = "https://signo.digitospace.com/api/events"


class SignoError(Exception):
    """Raised when Signo rejects or cannot receive an event."""


def send_event(
    title: str,
    body: str = "",
    *,
    namespace: str | None = None,
    priority: str = "default",
    payload: dict[str, Any] | None = None,
    timeout: int = 10,
) -> dict[str, Any]:
    """Emit one event; returns {eventId, delivered} on success.

    Raises [SignoError] on any failure so callers decide how loud to be.
    """
    ns = namespace or getattr(settings, "SIGNO_NAMESPACE", "")
    if not ns:
        raise SignoError("SIGNO_NAMESPACE is not configured")

    event: dict[str, Any] = {"namespace": ns, "title": title[:120], "priority": priority}
    if body:
        event["body"] = body[:500]
    if payload:
        event["payload"] = payload

    req = urllib.request.Request(
        SIGNO_URL,
        data=json.dumps(event).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status_code = resp.status
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:  # network/HTTP/parse — all failures are equal here
        raise SignoError(str(exc)) from exc
    if status_code != 202:
        raise SignoError(f"unexpected status {status_code}")
    logger.info("signo event %s delivered to %s device(s)", data.get("eventId"), data.get("delivered"))
    return data


def user_namespace(user) -> str | None:
    """Personal push channel for one account, or None when unconfigured.

    Personal events (habit streaks, goal wins, reminders) must go here —
    the global SIGNO_NAMESPACE reaches *every* subscriber's device, so
    pushing a habit name there leaked it to all users. A user only
    receives personal pushes once their device subscribes to this topic.
    """
    if getattr(user, "push_topic", ""):
        return user.push_topic
    template = getattr(settings, "SIGNO_USER_NAMESPACE_TEMPLATE", "")
    namespace = getattr(settings, "SIGNO_NAMESPACE", "")
    if template and namespace:
        return template.format(namespace=namespace, user_id=user.id)
    return None


def send_user_event(
    user,
    title: str,
    body: str = "",
    *,
    priority: str = "default",
    payload: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    """Best-effort push to one user's personal topic. Returns None when the
    user has no personal topic configured (never falls back to the global
    namespace — that would broadcast private data to every device)."""
    ns = user_namespace(user)
    if not ns:
        return None
    return send_event(title, body, namespace=ns, priority=priority, payload=payload)
