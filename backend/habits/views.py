import datetime as dt

from django.db import transaction
from django.utils import timezone
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from reminders.models import NotificationLog
from push.notify import notify_user

from automations.engine import day_complete, fire_event
from .models import Habit, HabitLog
from .serializers import HabitSerializer, HabitToggleSerializer, HabitWriteSerializer
from .services import completion_rate_30d, heatmap, habit_streaks, scheduled_days

STREAK_MILESTONES = (3, 7, 14, 30, 60, 100, 365)


def _celebrate_streak(user, habit: Habit, streak: int) -> None:
    """Record a streak milestone in the in-app feed and, best-effort, push it.
    The NotificationLog write must survive a Signo failure, so it gets its
    own try block and happens first."""
    if streak not in STREAK_MILESTONES:
        return
    title = f"{streak}-day streak: {habit.name}"
    body = "Keep the chain alive. Discipline compounds."
    NotificationLog.objects.create(
        user=user,
        title=title,
        body=body,
        kind="streak_milestone",
    )
    # FCM-first push (Signo fallback); best-effort — the milestone is
    # already recorded above.
    notify_user(
        user,
        title,
        body,
        payload={"kind": "streak_milestone", "habitId": habit.id, "streak": streak},
    )


class HabitViewSet(viewsets.ModelViewSet):
    """/api/v1/habits/ - CRUD + today checklist + toggle + history + heatmap."""

    serializer_class = HabitSerializer

    def get_serializer_class(self):
        if self.action in ("create", "update", "partial_update"):
            return HabitWriteSerializer
        return HabitSerializer

    def get_queryset(self):
        # Streak/rate math re-queries via habit.logs.filter(...), which clones
        # the related manager — a Prefetch cache here is silently discarded and
        # doubles the query load, so it was removed. The per-day map is fetched
        # directly in list_batches/history/today instead.
        qs = Habit.objects.filter(user=self.request.user)
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
        # All date math uses the configured TIME_ZONE (timezone.localdate).
        # dt.date.today() is server-UTC and made check-ins land on the wrong
        # calendar day whenever UTC "today" differs from the user's today.
        day = self._parse_date(request) or timezone.localdate()
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
        day = payload.validated_data.get("date") or timezone.localdate()
        # A future date would let a client pre-log tomorrow and inflate streaks.
        if day > timezone.localdate():
            return Response(
                {"detail": "Cannot check in for a future date."},
                status=400,
            )

        # Atomic read-modify-write: a double-tap or two racing requests
        # previously hit the uniq_habit_day constraint as a 500 or lost one
        # toggle. select_for_update serializes the flip on the row.
        with transaction.atomic():
            log, created = HabitLog.objects.select_for_update().get_or_create(
                habit=habit, date=day, defaults={"completed": True}
            )
            if not created:
                log.completed = not log.completed
                log.save(update_fields=["completed"])

        today_log = HabitLog.objects.filter(habit=habit, date=timezone.localdate()).first()
        stats = habit_streaks(habit)

        if log.completed:
            _celebrate_streak(request.user, habit, stats["current_streak"])
            # User-defined automations fire after the toggle commits; each
            # dispatch is best-effort and never breaks the toggle response.
            fire_event(
                request.user, "habit_done", habit=habit, streak=stats["current_streak"]
            )
            fire_event(
                request.user,
                "streak_reached",
                habit=habit,
                streak=stats["current_streak"],
            )
            if day_complete(request.user):
                fire_event(request.user, "all_habits_done", habit=habit)

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
        today = timezone.localdate()
        since = today - dt.timedelta(days=days - 1)
        done = set(
            habit.logs.filter(completed=True, date__gte=since).values_list("date", flat=True)
        )
        out = []
        day = since
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
    def history_batch(self, request):
        """/habits/history_batch/?days=180 -> per-habit history maps in ONE call.

        Replaces the mobile client's per-habit /history/ loop (one request
        per habit per tab visit) with a single request for all habits.
        """
        try:
            days = min(int(request.query_params.get("days", 180)), 365 * 2)
        except ValueError:
            days = 180
        today = timezone.localdate()
        since = today - dt.timedelta(days=days - 1)
        habits = list(self.get_queryset())
        done: dict[int, set[dt.date]] = {habit.id: set() for habit in habits}
        rows = (
            HabitLog.objects.filter(
                habit__in=habits, completed=True, date__gte=since
            ).values_list("habit_id", "date")
        )
        for habit_id, date in rows:
            done[habit_id].add(date)

        out = {}
        for habit in habits:
            streaks = habit_streaks(habit)
            out[str(habit.id)] = {
                "days": [
                    {"date": (since + dt.timedelta(days=o)).isoformat(), "completed": (since + dt.timedelta(days=o)) in done[habit.id]}
                    for o in range((today - since).days + 1)
                ],
                "streaks": {
                    "current": streaks["current_streak"],
                    "best": streaks["best_streak"],
                },
            }
        return Response({"days_span": days, "habits": out})

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
