from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from reminders.models import NotificationLog
from reminders.signo import SignoError, send_event

from .models import Goal
from .serializers import GoalSerializer


class GoalViewSet(viewsets.ModelViewSet):
    serializer_class = GoalSerializer

    def get_queryset(self):
        qs = Goal.objects.filter(user=self.request.user)
        status_param = self.request.query_params.get("status")
        if status_param:
            qs = qs.filter(status=status_param)
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        """/goals/{id}/complete/ -> mark achieved."""
        goal = self.get_object()
        goal.status = "achieved"
        goal.progress = 100
        goal.save(update_fields=["status", "progress"])
        try:
            send_event(
                title=f"Goal achieved: {goal.title}",
                body="Promise kept to yourself. Log it and set the next one.",
                priority="high",
                payload={"kind": "goal_achieved", "goalId": goal.id},
            )
            NotificationLog.objects.create(
                user=goal.user,
                title=f"Goal achieved: {goal.title}",
                body="Promise kept to yourself. Log it and set the next one.",
                kind="goal_achieved",
            )
        except SignoError:
            pass  # a push failure must never fail the achievement
        return Response(GoalSerializer(goal).data)
