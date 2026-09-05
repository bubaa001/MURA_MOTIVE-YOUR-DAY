"""Tiny local factories — deliberately dependency-free (no factory_boy)."""
import datetime as dt

from django.utils import timezone

from accounts.models import User
from .models import Habit


def make_user(username="tester"):
    return User.objects.create_user(username=username, password="test-pass-123")


def make_habit(user, *, name="Read 10 pages", category="mental", grace=0, days_ago=None):
    habit = Habit.objects.create(
        user=user,
        name=name,
        category=category,
        grace_days_per_week=grace,
    )
    if days_ago is not None:
        # created_at is auto_now_add, so backdate via update() (bypasses the hook)
        # to simulate a habit started in the past.
        Habit.objects.filter(pk=habit.pk).update(
            created_at=timezone.now() - dt.timedelta(days=days_ago)
        )
        habit.refresh_from_db()
    return habit
