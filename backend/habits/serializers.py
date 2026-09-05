from rest_framework import serializers

from .models import Habit, HabitLog
from .services import completion_rate_30d, habit_streaks


class HabitSerializer(serializers.ModelSerializer):
    current_streak = serializers.SerializerMethodField()
    best_streak = serializers.SerializerMethodField()
    completion_rate_30d = serializers.SerializerMethodField()

    class Meta:
        model = Habit
        fields = (
            "id", "name", "description", "icon", "color", "category",
            "grace_days_per_week", "is_active",
            "schedule_days",
            "current_streak", "best_streak", "completion_rate_30d",
            "created_at",
        )

    def _streaks(self, habit: Habit) -> dict[str, int]:
        if not hasattr(habit, "_streak_cache"):
            habit._streak_cache = habit_streaks(habit)
        return habit._streak_cache

    def get_current_streak(self, obj: Habit) -> int:
        return self._streaks(obj)["current_streak"]

    def get_best_streak(self, obj: Habit) -> int:
        return self._streaks(obj)["best_streak"]

    def get_completion_rate_30d(self, obj: Habit) -> int:
        if not hasattr(obj, "_rate_cache"):
            obj._rate_cache = completion_rate_30d(obj)
        return obj._rate_cache


class HabitWriteSerializer(serializers.ModelSerializer):
    schedule_days = serializers.ListField(
        child=serializers.IntegerField(min_value=1, max_value=7),
        required=False,
    )

    class Meta:
        model = Habit
        fields = (
            "id", "name", "description", "icon", "color", "category",
            "grace_days_per_week", "is_active",
            "schedule_days",
        )
        read_only_fields = ("id",)


class HabitToggleSerializer(serializers.Serializer):
    date = serializers.DateField(required=False, help_text="YYYY-MM-DD, defaults to today.")
