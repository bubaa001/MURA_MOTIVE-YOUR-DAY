"""TheFeeder Push section: compose + send broadcast notifications.

Campaigns go to every registered app device (FCM) AND every Signo
subscriber — the two audiences are different people, unlike personal
events where a user would be double-notified.
"""
import logging

from accounts.models import DeviceToken
from django.utils import timezone
from push import FcmError, fcm_configured, is_unregistered, send_fcm
from rest_framework import serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .models import NotificationLog, PushCampaign
from .signo import SignoError, send_event

logger = logging.getLogger(__name__)


class PushCampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = PushCampaign
        fields = ("id", "title", "body", "schedule", "send_time", "weekday", "is_active", "last_sent_date", "created_at")
        read_only_fields = ("id", "last_sent_date", "created_at")


def deliver_campaign(campaign: PushCampaign) -> dict:
    """Send one campaign to every audience. Returns a result summary.

    FCM reaches every installed app (no third-party app needed); Signo
    keeps reaching subscribers of the broadcast namespace. Signo failing no
    longer blocks the FCM leg (and vice versa).
    """
    payload = {"kind": "campaign", "campaign_id": campaign.id}
    delivered = 0
    if fcm_configured():
        for token in DeviceToken.objects.filter(is_active=True).values_list("token", flat=True):
            try:
                send_fcm(token, campaign.title, campaign.body, payload=payload)
                delivered += 1
            except FcmError as exc:
                if is_unregistered(exc):
                    DeviceToken.objects.filter(token=token).update(is_active=False)
                else:
                    logger.warning("campaign FCM push failed for %s…: %s", token[:12], exc)
    signo_result = send_event(
        campaign.title,
        campaign.body,
        payload=payload,
        priority="high" if campaign.schedule == "now" else "default",
    )
    delivered += signo_result.get("delivered", 0)
    return {"delivered": delivered, "fcm_delivered": delivered - signo_result.get("delivered", 0), "event_id": signo_result.get("eventId")}


class PushCampaignViewSet(viewsets.ModelViewSet):
    """Staff-only studio endpoint: /api/v1/feeder/push/."""

    queryset = PushCampaign.objects.all()
    serializer_class = PushCampaignSerializer
    permission_classes = (IsAdminUser,)
    http_method_names = ("get", "post", "patch", "delete", "head", "options")

    @action(detail=True, methods=["post"])
    def send(self, request, pk=None):
        """Send this campaign right now (whatever its schedule)."""
        campaign = self.get_object()
        try:
            result = deliver_campaign(campaign)
        except SignoError as exc:
            return Response({"detail": f"Signo push failed: {exc}"}, status=502)
        campaign.last_sent_date = timezone.localdate()
        campaign.save(update_fields=("last_sent_date",))
        return Response({"delivered": result.get("delivered", 0), "event_id": result.get("event_id")})

    @action(detail=True, methods=["post"])
    def test(self, request, pk=None):
        """Send now AND drop it into the caller's in-app feed so they can see
        it on their phone immediately (bell) while holding the device."""
        campaign = self.get_object()
        try:
            result = deliver_campaign(campaign)
        except SignoError as exc:
            return Response({"detail": f"Signo push failed: {exc}"}, status=502)
        NotificationLog.objects.create(
            user=request.user,
            title=campaign.title,
            body=campaign.body or "Push test",
            kind="general",
        )
        return Response(
            {
                "delivered": result.get("delivered", 0),
                "event_id": result.get("event_id"),
                "in_app": True,
            }
        )
