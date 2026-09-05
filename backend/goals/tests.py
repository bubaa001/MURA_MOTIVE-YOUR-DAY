from rest_framework.test import APITestCase

from accounts.models import User
from habits.factories_for_tests import make_habit


class GoalApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="goaler", password="test-pass-123")
        self.habit = make_habit(self.user, name="Gym")
        self.client.force_authenticate(self.user)

    def test_create_goal_with_linked_habits(self):
        res = self.client.post(
            "/api/v1/goals/",
            {"title": "Peak Physical Form", "category": "Fitness", "progress": 70,
             "linked_habit_ids": [self.habit.id]},
            format="json",
        )
        self.assertEqual(res.status_code, 201, res.content)
        self.assertEqual(res.json()["linked_habit_ids"], [self.habit.id])

    def test_cannot_link_someone_elses_habit(self):
        other = User.objects.create_user(username="other", password="test-pass-123")
        foreign = make_habit(other, name="Foreign")
        res = self.client.post(
            "/api/v1/goals/",
            {"title": "Cheater Goal", "linked_habit_ids": [foreign.id]},
            format="json",
        )
        self.assertEqual(res.status_code, 400)

    def test_complete_action(self):
        goal = self.client.post("/api/v1/goals/", {"title": "Read 12 books"}, format="json").json()
        res = self.client.post(f"/api/v1/goals/{goal['id']}/complete/")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "achieved")
        self.assertEqual(res.json()["progress"], 100)
