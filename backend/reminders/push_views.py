"""TheFeeder Push section: compose + send broadcast notifications.

Campaigns are delivered with Google's Firebase Cloud Messaging (FCM) to
every registered app device — MURA's own push channel, no third-party
app required. Signo is no longer part of the delivery path.
"""
import logging

from accounts.models import DeviceToken
from django.utils import timezone
from push import FcmError, fcm_configured, is_unregistered, send_fcm
from rest_framework import serializers, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .models import NotificationLog, PushCampaign

logger = logging.getLogger(__name__)


class PushCampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = PushCampaign
        fields = ("id", "title", "body", "schedule", "send_time", "weekday", "is_active", "last_sent_date", "created_at")
        read_only_fields = ("id", "last_sent_date", "created_at")


def deliver_campaign(campaign: PushCampaign) -> dict:
    """Send one campaign to every registered app device via FCM."""
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
    else:
        logger.warning("campaign send skipped: FCM is not configured (FCM_* missing from .env)")
    return {"delivered": delivered, "event_id": None}


class PushCampaignViewSet(viewsets.ModelViewSet):
    """Studio endpoint: /api/v1/feeder/push/.

    IsAdminUser = is_staff: every employee/reviewer account qualifies
    (they are created is_staff=True), so composing and testing pushes is
    part of the studio workflow. Content sync itself stays owner-only.
    """

    queryset = PushCampaign.objects.all()
    serializer_class = PushCampaignSerializer
    permission_classes = (IsAdminUser,)
    http_method_names = ("get", "post", "patch", "delete", "head", "options")

    @action(detail=True, methods=["post"])
    def send(self, request, pk=None):
        """Send this campaign right now (whatever its schedule)."""
        campaign = self.get_object()
        result = deliver_campaign(campaign)
        campaign.last_sent_date = timezone.localdate()
        campaign.save(update_fields=("last_sent_date",))
        return Response({"delivered": result.get("delivered", 0), "event_id": result.get("event_id")})

    @action(detail=True, methods=["post"])
    def test(self, request, pk=None):
        """Send now AND drop it into the caller's in-app feed so they can see
        it on their phone immediately (bell) while holding the device."""
        campaign = self.get_object()
        result = deliver_campaign(campaign)
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
