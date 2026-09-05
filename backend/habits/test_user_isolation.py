"""Per-user data isolation across every owned resource.

User B must never see user A's habits, goals, journal entries, memories,
priorities or reminders - lists come back empty and detail reads 404.
"""
import datetime as dt

from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import User
from goals.models import Goal
from habits.factories_for_tests import make_habit
from habits.models import HabitLog
from journal.models import JournalEntry, Memory
from priorities.models import Priority
from reminders.models import Reminder


class UserIsolationTests(APITestCase):
    def setUp(self):
        self.alice = User.objects.create_user(username="alice", password="test-pass-123")
        self.bob = User.objects.create_user(username="bob", password="test-pass-123")

        # Alice owns one of everything.
        self.habit = make_habit(self.alice, name="Alice habit")
        HabitLog.objects.create(habit=self.habit)
        self.goal = Goal.objects.create(user=self.alice, title="Alice goal")
        self.entry = JournalEntry.objects.create(
            user=self.alice, title="Alice entry", body="secret musings"
        )
        self.memory = Memory.objects.create(
            user=self.alice, title="Alice memory", date=dt.date.today()
        )
        self.priority = Priority.objects.create(user=self.alice, title="Alice priority")
        self.reminder = Reminder.objects.create(
            user=self.alice, title="Alice reminder", time="07:00"
        )

        self.client.force_authenticate(self.bob)

    def test_habits_isolated(self):
        self.assertEqual(self.client.get("/api/v1/habits/").json()["results"], [])
        res = self.client.get("/api/v1/habits/%d/" % self.habit.id)
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_bob_cannot_toggle_alices_habit(self):
        before = HabitLog.objects.filter(habit=self.habit).count()
        res = self.client.post("/api/v1/habits/%d/toggle/" % self.habit.id, {}, format="json")
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        # No log was created or flipped by the rejected request.
        self.assertEqual(HabitLog.objects.filter(habit=self.habit).count(), before)
        self.assertTrue(
            HabitLog.objects.filter(habit=self.habit, completed=True).exists()
        )

    def test_goals_isolated(self):
        self.assertEqual(self.client.get("/api/v1/goals/").json()["results"], [])
        self.assertEqual(
            self.client.get("/api/v1/goals/%d/" % self.goal.id).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_journal_entries_isolated(self):
        results = self.client.get("/api/v1/journal/entries/").json()["results"]
        self.assertEqual(results, [])
        self.assertEqual(
            self.client.get("/api/v1/journal/entries/%d/" % self.entry.id).status_code,
            status.HTTP_404_NOT_FOUND,
        )
        # Bob's search cannot surface Alice's body text either.
        hits = self.client.get("/api/v1/journal/entries/?search=secret").json()["results"]
        self.assertEqual(hits, [])

    def test_memories_isolated(self):
        self.assertEqual(self.client.get("/api/v1/memories/").json()["results"], [])
        self.assertEqual(
            self.client.get("/api/v1/memories/%d/" % self.memory.id).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_priorities_isolated(self):
        self.assertEqual(self.client.get("/api/v1/priorities/").json()["results"], [])
        self.assertEqual(
            self.client.get("/api/v1/priorities/%d/" % self.priority.id).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_reminders_isolated(self):
        self.assertEqual(self.client.get("/api/v1/reminders/").json()["results"], [])
        self.assertEqual(
            self.client.get("/api/v1/reminders/%d/" % self.reminder.id).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_bob_cannot_delete_alices_resources(self):
        urls = (
            "/api/v1/habits/%d/" % self.habit.id,
            "/api/v1/goals/%d/" % self.goal.id,
            "/api/v1/journal/entries/%d/" % self.entry.id,
            "/api/v1/memories/%d/" % self.memory.id,
            "/api/v1/priorities/%d/" % self.priority.id,
            "/api/v1/reminders/%d/" % self.reminder.id,
        )
        for url in urls:
            with self.subTest(url=url):
                res = self.client.delete(url)
                self.assertIn(res.status_code, (status.HTTP_404_NOT_FOUND,))

        # Nothing was actually deleted.
        self.assertTrue(type(self.habit).objects.filter(pk=self.habit.pk).exists())
        self.assertTrue(Goal.objects.filter(pk=self.goal.pk).exists())
        self.assertTrue(JournalEntry.objects.filter(pk=self.entry.pk).exists())
        self.assertTrue(Memory.objects.filter(pk=self.memory.pk).exists())
        self.assertTrue(Priority.objects.filter(pk=self.priority.pk).exists())
        self.assertTrue(Reminder.objects.filter(pk=self.reminder.pk).exists())

    def test_reorder_rejects_foreign_priority_ids(self):
        res = self.client.post(
            "/api/v1/priorities/reorder/", {"ordered_ids": [self.priority.id]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_heatmap_only_counts_own_logs(self):
        data = self.client.get("/api/v1/habits/heatmap_data/?weeks=1").json()
        days = data["weeks"][-1]["days"]
        today_entry = days[-1]
        self.assertEqual(today_entry["ratio"], 0.0)  # bob did nothing today
