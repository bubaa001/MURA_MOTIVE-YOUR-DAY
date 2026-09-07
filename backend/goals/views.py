from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from reminders.models import NotificationLog
from reminders.signo import send_user_event

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
        try:
            send_user_event(
                goal.user,
                title,
                body,
                priority="high",
                payload={"kind": "goal_achieved", "goalId": goal.id},
            )
        except Exception:
            pass  # a push failure must never fail the achievement
        return Response(GoalSerializer(goal).data)
