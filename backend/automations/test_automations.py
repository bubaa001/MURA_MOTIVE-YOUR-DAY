"""Automations: API contract, rule engine dispatch, and scheduled nudges."""
import datetime as dt

from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from goals.models import Goal
from habits.factories_for_tests import make_habit, make_user
from habits.models import HabitLog
from reminders.models import NotificationLog

from .engine import day_complete, fire_event
from .models import AutomationRule


def _rule(user, trigger, config=None, action=None, name="My rule", active=True):
    return AutomationRule.objects.create(
        user=user,
        name=name,
        trigger_type=trigger,
        trigger_config=config or {},
        action_config=action or {"title": "Well done on {habit}!", "body": "Streak: {streak}"},
        is_active=active,
    )


class AutomationApiTests(APITestCase):
    def setUp(self):
        self.user = make_user("autoowner")
        self.client.force_authenticate(self.user)

    def test_list_scopes_to_owner(self):
        other = make_user("autoother")
        _rule(other, "habit_done")
        _rule(self.user, "habit_done", name="Mine")
        body = self.client.get("/api/v1/automations/").json()
        self.assertEqual([r["name"] for r in body["results"]], ["Mine"])

    def test_create_validates_daily_nudge_time(self):
        res = self.client.post(
            "/api/v1/automations/",
            {"name": "Nudge", "trigger_type": "daily_nudge", "trigger_config": {"time": "25:99"}},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)

        res = self.client.post(
            "/api/v1/automations/",
            {
                "name": "Nudge",
                "trigger_type": "daily_nudge",
                "trigger_config": {"time": "21:30", "only_if_incomplete": True},
                "action_config": {"title": "Close the day", "body": "Habits still open"},
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.content)
        self.assertTrue(res.json()["trigger_config"]["only_if_incomplete"])

    def test_create_validates_streak_target(self):
        res = self.client.post(
            "/api/v1/automations/",
            {"name": "S", "trigger_type": "streak_reached", "trigger_config": {"streak": "seven"}},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)

    def test_habit_id_must_belong_to_caller(self):
        stranger = make_user("autostranger")
        foreign = make_habit(stranger)
        res = self.client.post(
            "/api/v1/automations/",
            {
                "name": "Watch",
                "trigger_type": "habit_done",
                "trigger_config": {"habit_id": foreign.id},
            },
            format="json",
        )
        # IDOR guard: another user's habit id is indistinguishable from a
        # nonexistent one.
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST, res.content)

    def test_toggle_endpoint_flips_active(self):
        rule = _rule(self.user, "habit_done")
        res = self.client.post(f"/api/v1/automations/{rule.id}/toggle/", format="json")
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.content)
        self.assertFalse(res.json()["is_active"])

    def test_detail_read_is_scoped(self):
        other = make_user("autoother2")
        rule = _rule(other, "habit_done")
        self.assertEqual(
            self.client.get(f"/api/v1/automations/{rule.id}/").status_code, 404
        )


class EngineDispatchTests(APITestCase):
    """Reactive rules fire through the real habit-toggle / goal-complete views."""

    def setUp(self):
        self.user = make_user("engineuser")
        self.client.force_authenticate(self.user)
        self.habit = make_habit(self.user)

    def _toggle(self):
        return self.client.post(
            f"/api/v1/habits/{self.habit.id}/toggle/", format="json"
        )

    def test_habit_done_rule_fires_and_renders_placeholders(self):
        _rule(
            self.user,
            "habit_done",
            action={"title": "Big win: {habit}", "body": "You are at {streak} day(s)"},
        )
        res = self._toggle()
        self.assertEqual(res.status_code, 200, res.content)
        note = NotificationLog.objects.filter(user=self.user, kind="automation").get()
        self.assertEqual(note.title, f"Big win: {self.habit.name}")
        self.assertEqual(note.body, "You are at 1 day(s)")

    def test_specific_habit_rule_ignores_other_habits(self):
        other_habit = make_habit(self.user, name="Meditate")
        _rule(self.user, "habit_done", config={"habit_id": other_habit.id})
        self._toggle()
        self.assertFalse(
            NotificationLog.objects.filter(user=self.user, kind="automation").exists()
        )

    def test_streak_reached_fires_exactly_at_target(self):
        # The streak engine ignores logs predating habit creation, so the
        # habit must be backdated before backfilling its history.
        habit = make_habit(self.user, days_ago=5)
        rule = _rule(
            self.user,
            "streak_reached",
            config={"streak": 3},
            action={"title": "{streak} days strong"},
        )
        # Two past completions, so today's toggle makes the streak exactly 3.
        today = timezone.localdate()
        for back in (1, 2):
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=back), completed=True)
        res = self.client.post(f"/api/v1/habits/{habit.id}/toggle/", format="json")
        self.assertEqual(res.status_code, 200, res.content)
        rule.refresh_from_db()
        note = NotificationLog.objects.filter(user=self.user, kind="automation").get()
        self.assertEqual(note.title, "3 days strong")
        self.assertEqual(rule.last_fired_date, today)

    def test_daily_dedup_no_double_celebration(self):
        # Same-day re-fire (toggle off, toggle on) is suppressed.
        _rule(self.user, "habit_done")
        self._toggle()
        self._toggle()  # off
        self._toggle()  # on again — same day, must not re-fire
        self.assertEqual(
            NotificationLog.objects.filter(user=self.user, kind="automation").count(), 1
        )

    def test_all_habits_done_fires_on_last_check(self):
        _rule(self.user, "all_habits_done", action={"title": "Day complete"})
        self._toggle()
        self.assertTrue(
            NotificationLog.objects.filter(
                user=self.user, kind="automation", title="Day complete"
            ).exists()
        )

    def test_goal_achieved_rule_fires_once(self):
        goal = Goal.objects.create(user=self.user, title="Run a 10k")
        _rule(self.user, "goal_achieved", action={"title": "Goal smashed: {goal}"})
        for _ in range(2):  # second complete is an idempotent no-op
            res = self.client.post(f"/api/v1/goals/{goal.id}/complete/", format="json")
            self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(
            NotificationLog.objects.filter(
                user=self.user, kind="automation", title="Goal smashed: Run a 10k"
            ).count(),
            1,
        )

    def test_inactive_rule_never_fires(self):
        _rule(self.user, "habit_done", active=False)
        self._toggle()
        self.assertFalse(
            NotificationLog.objects.filter(user=self.user, kind="automation").exists()
        )


class DailyNudgeCommandTests(APITestCase):
    def test_nudge_fires_in_window_and_dedupes(self):
        user = make_user("nudgeuser")
        habit = make_habit(user)
        now = timezone.localtime()
        rule = AutomationRule.objects.create(
            user=user,
            name="Evening push",
            trigger_type="daily_nudge",
            trigger_config={
                "time": (now - dt.timedelta(minutes=30)).strftime("%H:%M"),
                "only_if_incomplete": False,
            },
            action_config={"title": "Evening", "body": "Finish strong"},
        )
        call_command("run_automations", stdout=_Collector())
        rule.refresh_from_db()
        self.assertEqual(rule.last_fired_date, now.date())
        self.assertTrue(
            NotificationLog.objects.filter(user=user, kind="automation", title="Evening").exists()
        )
        # Second same-day run is a no-op.
        call_command("run_automations", stdout=_Collector())
        self.assertEqual(
            NotificationLog.objects.filter(user=user, kind="automation", title="Evening").count(), 1
        )
        # The habit stays untouched by nudges.
        self.assertFalse(HabitLog.objects.filter(habit=habit).exists())

    def test_only_if_incomplete_holds_when_habits_open(self):
        user = make_user("nudgeopen")
        make_habit(user)
        now = timezone.localtime()
        AutomationRule.objects.create(
            user=user,
            name="Held nudge",
            trigger_type="daily_nudge",
            trigger_config={
                "time": (now - dt.timedelta(minutes=30)).strftime("%H:%M"),
                "only_if_incomplete": True,
            },
            action_config={"title": "Held"},
        )
        call_command("run_automations", stdout=_Collector())
        self.assertFalse(
            NotificationLog.objects.filter(user=user, kind="automation").exists()
        )

    def test_dry_run_fires_nothing(self):
        user = make_user("driednudge")
        now = timezone.localtime()
        AutomationRule.objects.create(
            user=user,
            name="Dry",
            trigger_type="daily_nudge",
            trigger_config={"time": (now - dt.timedelta(minutes=30)).strftime("%H:%M")},
            action_config={"title": "Dry"},
        )
        call_command("run_automations", "--dry-run", stdout=_Collector())
        self.assertFalse(
            NotificationLog.objects.filter(user=user, kind="automation").exists()
        )


class DayCompleteTests(APITestCase):
    def test_no_scheduled_habits_is_not_complete(self):
        user = make_user("emptyday")
        self.assertFalse(day_complete(user))

    def test_all_done_today_is_complete(self):
        user = make_user("fullday")
        habit = make_habit(user)
        HabitLog.objects.create(habit=habit, date=timezone.localdate(), completed=True)
        self.assertTrue(day_complete(user))


class _Collector:
    """call_command needs a stdout-ish object; keep it minimal."""

    def write(self, *_a, **_k):
        pass

    def flush(self):
        pass
