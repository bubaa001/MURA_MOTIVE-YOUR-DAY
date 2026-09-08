from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from automations.engine import fire_event
from push.notify import notify_user
from reminders.models import NotificationLog

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
        if goal.status == "achieved":
            # Idempotent: a double-tap must not re-celebrate or re-fire
            # goal automations for a goal that is already achieved.
            return Response(GoalSerializer(goal).data)
        goal.status = "achieved"
        goal.progress = 100
        goal.save(update_fields=["status", "progress"])
        title = f"Goal achieved: {goal.title}"
        body = "Promise kept to yourself. Log it and set the next one."
        # In-app record first so it survives a push failure; the push goes to
        # the user's personal topic only — the global namespace would
        # broadcast the goal title to every other user's device.
        NotificationLog.objects.create(
            user=goal.user,
            title=title,
            body=body,
            kind="goal_achieved",
        )
        # FCM-first push (Signo fallback); a push failure must never fail
        # the achievement.
        notify_user(
            goal.user,
            title,
            body,
            payload={"kind": "goal_achieved", "goalId": goal.id},
        )
        fire_event(goal.user, "goal_achieved", goal=goal)
        return Response(GoalSerializer(goal).data)
