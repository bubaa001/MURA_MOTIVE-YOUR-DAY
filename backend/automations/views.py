from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import AutomationRule
from .serializers import AutomationRuleSerializer


class AutomationRuleViewSet(viewsets.ModelViewSet):
    """/api/v1/automations/ — the signed-in user's rules (full CRUD)."""

    serializer_class = AutomationRuleSerializer

    def get_queryset(self):
        return AutomationRule.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=["post"])
    def toggle(self, request, pk=None):
        """/automations/{id}/toggle/ — pause/resume without a full PATCH."""
        rule = self.get_object()
        rule.is_active = not rule.is_active
        rule.save(update_fields=["is_active", "updated_at"])
        return Response(self.get_serializer(rule).data)
