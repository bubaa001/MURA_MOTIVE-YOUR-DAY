import datetime as dt

from django.utils import timezone

from rest_framework.test import APITestCase

from .factories_for_tests import make_habit, make_user
from .models import HabitLog
from .services import completion_rate_30d, habit_streaks


class HabitToggleTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.habit = make_habit(self.user)
        self.client.force_authenticate(self.user)

    def test_toggle_creates_and_flips_log(self):
        res = self._toggle()
        self.assertTrue(res["completed"])
        self.assertEqual(res["current_streak"], 1)
        res = self._toggle()
        self.assertFalse(res["completed"])
        self.assertEqual(HabitLog.objects.filter(habit=self.habit).count(), 1)

    def test_today_checklist(self):
        self.client.force_authenticate(self.user)
        res = self.client.get("/api/v1/habits/today/")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["items"][0]["name"], self.habit.name)

    def _toggle(self):
        response = self.client.post(f"/api/v1/habits/{self.habit.id}/toggle/", {}, format="json")
        self.assertEqual(response.status_code, 200)
        return response.json()


class StreakTests(APITestCase):
    def setUp(self):
        self.user = make_user()

    def test_consecutive_days(self):
        habit = make_habit(self.user, days_ago=5)
        today = timezone.localdate()
        for offset in range(3):  # yesterday ... three days back
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        stats = habit_streaks(habit)
        self.assertEqual(stats["current_streak"], 3)
        self.assertEqual(stats["best_streak"], 3)

    def test_unchecked_today_is_pending_not_broken(self):
        habit = make_habit(self.user, days_ago=5)
        today = timezone.localdate()
        HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=1))
        stats = habit_streaks(habit)
        self.assertEqual(stats["current_streak"], 1)

    def test_missed_day_breaks_without_grace(self):
        habit = make_habit(self.user, days_ago=6)
        today = timezone.localdate()
        for offset in (0, 2, 3):
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        stats = habit_streaks(habit)
        self.assertEqual(stats["current_streak"], 1)   # only yesterday's run
        self.assertEqual(stats["best_streak"], 2)      # the earlier two-day pair

    def test_single_grace_day_survives(self):
        habit = make_habit(self.user, grace=1, days_ago=8)
        today = timezone.localdate()
        for offset in range(7):  # 7 straight days ending yesterday
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        # poke one hole three days back — forgiven by the grace budget of 1
        hole = today - dt.timedelta(days=3)
        HabitLog.objects.filter(habit=habit, date=hole).delete()
        stats = habit_streaks(habit)
        self.assertEqual(stats["current_streak"], 7)
        self.assertEqual(stats["best_streak"], 7)

    def test_two_consecutive_misses_break_even_with_grace(self):
        habit = make_habit(self.user, grace=1, days_ago=10)
        today = timezone.localdate()
        for offset in range(8):
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        HabitLog.objects.filter(habit=habit, date=today - dt.timedelta(days=4)).delete()
        HabitLog.objects.filter(habit=habit, date=today - dt.timedelta(days=3)).delete()
        stats = habit_streaks(habit)
        # Double miss breaks hard: only the two most recent days survive,
        # even though the first of the two misses was individually forgivable.
        self.assertEqual(stats["current_streak"], 2)
        self.assertEqual(stats["best_streak"], 5)  # 4 completions + 1 frozen day

    def test_weekly_window_caps_forgiveness(self):
        habit = make_habit(self.user, grace=1, days_ago=14)
        today = timezone.localdate()
        for offset in range(13):
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        # Two isolated holes inside the same rolling week -> second breaks the old run.
        for back in (9, 11):
            HabitLog.objects.filter(habit=habit, date=today - dt.timedelta(days=back)).delete()
        stats = habit_streaks(habit)
        # Everything after the newest hole survives as the trailing run.
        self.assertLessEqual(stats["current_streak"], 8)

    def test_completion_rate_30d(self):
        habit = make_habit(self.user, days_ago=30)
        today = timezone.localdate()
        for offset in range(15):
            HabitLog.objects.create(habit=habit, date=today - dt.timedelta(days=offset + 1))
        rate = completion_rate_30d(habit)
        self.assertEqual(rate, 50)
