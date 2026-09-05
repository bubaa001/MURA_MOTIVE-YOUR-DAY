"""API-shape tests for the habits engine endpoints."""
import datetime as dt
from numbers import Real

from rest_framework import status
from rest_framework.test import APITestCase

from .factories_for_tests import make_habit, make_user
from .models import HabitLog


class TodayChecklistTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.habit = make_habit(self.user, name="Read 10 pages")
        self.client.force_authenticate(self.user)

    def test_checklist_shape_matches_contract(self):
        res = self.client.get("/api/v1/habits/today/")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        body = res.json()
        self.assertEqual(body["date"], dt.date.today().isoformat())
        (item,) = body["items"]
        self.assertEqual(
            set(item.keys()),
            {"habit_id", "name", "icon", "color", "category", "completed", "log_id"},
        )
        self.assertEqual(item["habit_id"], self.habit.id)
        self.assertFalse(item["completed"])
        self.assertIsNone(item["log_id"])

    def test_checklist_reflects_toggle(self):
        self.client.post(f"/api/v1/habits/{self.habit.id}/toggle/", {}, format="json")
        (item,) = self.client.get("/api/v1/habits/today/").json()["items"]
        self.assertTrue(item["completed"])
        self.assertIsNotNone(item["log_id"])
        # And back off again.
        self.client.post(f"/api/v1/habits/{self.habit.id}/toggle/", {}, format="json")
        (item,) = self.client.get("/api/v1/habits/today/").json()["items"]
        self.assertFalse(item["completed"])

    def test_inactive_habits_excluded_from_checklist(self):
        from .models import Habit

        make_habit(self.user, name="Archived")
        Habit.objects.filter(user=self.user, name="Archived").update(is_active=False)
        names = [i["name"] for i in self.client.get("/api/v1/habits/today/").json()["items"]]
        self.assertEqual(names, ["Read 10 pages"])


class ToggleTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.habit = make_habit(self.user)
        self.client.force_authenticate(self.user)

    def _toggle(self, payload=None):
        return self.client.post(
            f"/api/v1/habits/{self.habit.id}/toggle/", payload or {}, format="json"
        )

    def test_toggle_twice_flips_state(self):
        first = self._toggle()
        self.assertEqual(first.status_code, status.HTTP_200_OK)
        self.assertTrue(first.json()["completed"])
        second = self._toggle()
        self.assertFalse(second.json()["completed"])
        third = self._toggle()
        self.assertTrue(third.json()["completed"])
        self.assertEqual(HabitLog.objects.filter(habit=self.habit).count(), 1)

    def test_toggle_explicit_date(self):
        yesterday = (dt.date.today() - dt.timedelta(days=1)).isoformat()
        res = self._toggle({"date": yesterday})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        body = res.json()
        self.assertEqual(body["date"], yesterday)
        self.assertTrue(HabitLog.objects.filter(habit=self.habit, date=yesterday).exists())

    def test_toggle_rejects_malformed_date(self):
        res = self._toggle({"date": "not-a-date"})
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_toggle_returns_streak_stats_and_completed_today(self):
        body = self._toggle().json()
        for key in ("current_streak", "best_streak", "completion_rate_30d", "completed_today"):
            self.assertIn(key, body)
        self.assertEqual(body["current_streak"], 1)
        self.assertTrue(body["completed_today"])
        off = self._toggle().json()
        self.assertFalse(off["completed"])
        self.assertFalse(off["completed_today"])

    def test_completed_today_tracks_today_even_when_toggling_past_date(self):
        yesterday = (dt.date.today() - dt.timedelta(days=1)).isoformat()
        body = self._toggle({"date": yesterday}).json()
        self.assertTrue(body["completed"])          # yesterday got done...
        self.assertFalse(body["completed_today"])   # ...but today still pending


class HistoryTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.habit = make_habit(self.user, days_ago=10)
        today = dt.date.today()
        for offset in range(3):  # today, yesterday, 2 days ago
            HabitLog.objects.create(
                habit=self.habit, date=today - dt.timedelta(days=offset)
            )
        self.client.force_authenticate(self.user)

    def test_history_day_count_and_flags(self):
        res = self.client.get("/api/v1/habits/%d/history/?days=7" % self.habit.id)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        body = res.json()
        self.assertEqual(len(body["days"]), 7)
        done = {d["date"] for d in body["days"] if d["completed"]}
        expected = {
            (dt.date.today() - dt.timedelta(days=o)).isoformat() for o in range(3)
        }
        self.assertEqual(done, expected)
        for day in body["days"]:
            self.assertEqual(set(day.keys()), {"date", "completed"})
        # Contract key names on the history endpoint: current/best.
        self.assertEqual(body["streaks"]["current"], 3)
        self.assertEqual(body["streaks"]["best"], 3)

    def test_history_default_is_180_days(self):
        body = self.client.get(f"/api/v1/habits/{self.habit.id}/history/").json()
        self.assertEqual(len(body["days"]), 180)

    def test_history_bad_days_param_falls_back(self):
        body = self.client.get(f"/api/v1/habits/{self.habit.id}/history/?days=abc").json()
        self.assertEqual(len(body["days"]), 180)


class HeatmapTests(APITestCase):
    def setUp(self):
        self.user = make_user()
        self.habit = make_habit(self.user, days_ago=14)
        HabitLog.objects.create(habit=self.habit, date=dt.date.today())
        self.client.force_authenticate(self.user)

    def test_heatmap_structure(self):
        res = self.client.get("/api/v1/habits/heatmap_data/?weeks=4")
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        weeks = res.json()["weeks"]
        self.assertEqual(len(weeks), 4)
        today = dt.date.today()
        monday_of_this_week = today - dt.timedelta(days=today.weekday())
        expected_start = monday_of_this_week - dt.timedelta(weeks=3)
        for i, week in enumerate(weeks):
            self.assertEqual(set(week.keys()), {"week_start", "days"})
            self.assertEqual(
                week["week_start"],
                (expected_start + dt.timedelta(weeks=i)).isoformat(),
            )
            for day in week["days"]:
                self.assertEqual(set(day.keys()), {"date", "ratio", "level"})
                self.assertIsInstance(day["ratio"], Real)
                self.assertGreaterEqual(day["ratio"], 0)
                self.assertIn(day["level"], (0, 1, 2, 3, 4))

    def test_heatmap_today_is_maxed_when_all_habits_done(self):
        weeks = self.client.get("/api/v1/habits/heatmap_data/?weeks=1").json()["weeks"]
        last_days = weeks[-1]["days"]
        today_entry = last_days[-1]
        self.assertEqual(today_entry["date"], dt.date.today().isoformat())
        self.assertEqual(today_entry["level"], 4)
        self.assertEqual(today_entry["ratio"], 1.0)

    def test_heatmap_excludes_other_users_habits(self):
        other = make_user(username="shadow")
        foreign = make_habit(other, name="Foreign")
        HabitLog.objects.create(habit=foreign, date=dt.date.today())
        weeks = self.client.get("/api/v1/habits/heatmap_data/?weeks=1").json()["weeks"]
        today_entry = weeks[-1]["days"][-1]
        self.assertEqual(today_entry["ratio"], 1.0)  # still just our own single habit
