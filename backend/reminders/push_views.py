"""TheFeeder Push section: compose + send broadcast notifications via Signo."""
from django.utils import timezone
from rest_framework import serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response

from .models import PushCampaign
from .signo import SignoError, send_event


class PushCampaignSerializer(serializers.ModelSerializer):
    class Meta:
        model = PushCampaign
        fields = ("id", "title", "body", "schedule", "send_time", "weekday", "is_active", "last_sent_date", "created_at")
        read_only_fields = ("id", "last_sent_date", "created_at")


def deliver_campaign(campaign: PushCampaign) -> dict:
    """Send one campaign to every Signo-subscribed device. Returns result."""
    return send_event(
        campaign.title,
        campaign.body,
        payload={"kind": "campaign", "campaign_id": campaign.id},
        priority="high" if campaign.schedule == "now" else "default",
    )


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
        return Response({"delivered": result.get("delivered", 0), "event_id": result.get("eventId")})
