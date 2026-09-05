import datetime as dt

from django.db.models import Prefetch
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from reminders.models import NotificationLog
from reminders.signo import SignoError, send_event

from .models import Habit, HabitLog
from .serializers import HabitSerializer, HabitToggleSerializer, HabitWriteSerializer
from .services import completion_rate_30d, heatmap, habit_streaks, scheduled_days

STREAK_MILESTONES = (3, 7, 14, 30, 60, 100, 365)


def _celebrate_streak(user, habit: Habit, streak: int) -> None:
    """Fire a Signo push when a streak hits a milestone. Best-effort: a push
    failure must never fail the toggle itself."""
    if streak not in STREAK_MILESTONES:
        return
    try:
        send_event(
            title=f"{streak}-day streak: {habit.name}",
            body="Keep the chain alive. Discipline compounds.",
            priority="default",
            payload={"kind": "streak_milestone", "habitId": habit.id, "streak": streak},
        )
        NotificationLog.objects.create(
            user=user,
            title=f"{streak}-day streak: {habit.name}",
            body="Keep the chain alive. Discipline compounds.",
            kind="streak_milestone",
        )
    except SignoError:
        pass


class HabitViewSet(viewsets.ModelViewSet):
    """/api/v1/habits/ - CRUD + today checklist + toggle + history + heatmap."""

    serializer_class = HabitSerializer

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return HabitWriteSerializer
        return HabitSerializer

    def get_queryset(self):
        qs = Habit.objects.filter(user=self.request.user).prefetch_related(
            Prefetch("logs", queryset=HabitLog.objects.filter(completed=True))
        )
        is_active = self.request.query_params.get("is_active")
        if is_active is not None:
            qs = qs.filter(is_active=is_active.lower() in {"1", "true"})
        else:
            # Contract: lists are active-only; ?is_active=false opts back in.
            qs = qs.filter(is_active=True)
        category = self.request.query_params.get("category")
        if category:
            qs = qs.filter(category=category)
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def _reserialize(self, response):
        """Answer create/update with the full Habit shape (computed streak
        fields included), matching the client's Habit type."""
        if response.status_code < 300 and response.data is not None:
            instance = Habit.objects.get(pk=response.data["id"])
            response.data = HabitSerializer(instance, context=self.get_serializer_context()).data
        return response

    def create(self, request, *args, **kwargs):
        return self._reserialize(super().create(request, *args, **kwargs))

    def update(self, request, *args, **kwargs):
        return self._reserialize(super().update(request, *args, **kwargs))

    @action(detail=False, methods=["get"])
    def today(self, request):
        """/habits/today/ -> today's checklist with completion state."""
        day = self._parse_date(request) or dt.date.today()
        logs = {
            log.habit_id: log for log in HabitLog.objects.filter(habit__user=request.user, date=day)
        }
        items = []
        for habit in self.get_queryset().filter(is_active=True):
            if day.isoweekday() not in scheduled_days(habit):
                continue
            log = logs.get(habit.id)
            items.append(
                {
                    "habit_id": habit.id,
                    "name": habit.name,
                    "icon": habit.icon,
                    "color": habit.color,
                    "category": habit.category,
                    "completed": bool(log and log.completed),
                    "log_id": log.id if log else None,
                }
            )
        return Response({"date": day.isoformat(), "items": items})

    @action(detail=True, methods=["post"])
    def toggle(self, request, pk=None):
        """/habits/{id}/toggle/ - flip completion for a date, return fresh stats."""
        habit = self.get_object()
        payload = HabitToggleSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        day = payload.validated_data.get("date") or dt.date.today()

        log, created = HabitLog.objects.get_or_create(
            habit=habit, date=day, defaults={"completed": True}
        )
        if not created:
            log.completed = not log.completed
            log.save(update_fields=["completed"])

        today_log = HabitLog.objects.filter(habit=habit, date=dt.date.today()).first()
        stats = habit_streaks(habit)

        if log.completed:
            _celebrate_streak(request.user, habit, stats["current_streak"])

        return Response(
            {
                "habit_id": habit.id,
                "date": day.isoformat(),
                "completed": log.completed,
                # Contract name for the today flag; equals the toggled-day flag
                # unless an explicit past date was toggled.
                "completed_today": bool(today_log and today_log.completed),
                **stats,
                "completion_rate_30d": completion_rate_30d(habit),
            }
        )

    @action(detail=True, methods=["get"])
    def history(self, request, pk=None):
        """/habits/{id}/history/?days=180 -> per-day completion map + streaks."""
        habit = self.get_object()
        try:
            days = min(int(request.query_params.get("days", 180)), 365 * 2)
        except ValueError:
            days = 180
        since = dt.date.today() - dt.timedelta(days=days - 1)
        done = set(
            habit.logs.filter(completed=True, date__gte=since).values_list("date", flat=True)
        )
        out = []
        day = since
        today = dt.date.today()
        while day <= today:
            out.append({"date": day.isoformat(), "completed": day in done})
            day += dt.timedelta(days=1)
        streaks = habit_streaks(habit)
        return Response(
            {
                "days": out,
                # Contract key names: current/best (not current_streak/best_streak).
                "streaks": {
                    "current": streaks["current_streak"],
                    "best": streaks["best_streak"],
                },
            }
        )

    @action(detail=False, methods=["get"])
    def heatmap_data(self, request):
        """/habits/heatmap_data/?weeks=26 -> consistency grid (Habits screen)."""
        try:
            weeks = min(int(request.query_params.get("weeks", 26)), 52)
        except ValueError:
            weeks = 26
        return Response({"weeks": heatmap(request.user, weeks)})

    def _parse_date(self, request):
        raw = request.query_params.get("date")
        if not raw:
            return None
        try:
            return dt.date.fromisoformat(raw)
        except ValueError:
            return None
