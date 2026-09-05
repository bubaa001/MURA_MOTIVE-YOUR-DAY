from rest_framework import serializers

from habits.models import Habit
from .models import Goal


class GoalSerializer(serializers.ModelSerializer):
    linked_habit_ids = serializers.PrimaryKeyRelatedField(
        source="linked_habits",
        many=True,
        required=False,
        queryset=Habit.objects.none(),
    )

    class Meta:
        model = Goal
        fields = (
            "id", "title", "description", "goal_type", "horizon", "category", "target_date",
            "status", "progress", "linked_habit_ids", "created_at",
        )
        read_only_fields = ("id", "created_at")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        request = self.context.get("request")
        if request is not None:
            # Scope habit choices to the requesting user. ManyRelatedField
            # validates through its child relation, so patch that queryset.
            self.fields["linked_habit_ids"].child_relation.queryset = Habit.objects.filter(
                user=request.user
            )

    def validate_progress(self, value: int) -> int:
        if not 0 <= value <= 100:
            raise serializers.ValidationError("Progress must be between 0 and 100.")
        return value
