import datetime as dt

from rest_framework import serializers

from .models import AutomationRule


class AutomationRuleSerializer(serializers.ModelSerializer):
    """Create/update/list automation rules; trigger/action configs are
    validated per trigger type so bad payloads never reach the engine."""

    class Meta:
        model = AutomationRule
        fields = (
            "id", "name", "trigger_type", "trigger_config", "action_type",
            "action_config", "is_active", "last_fired_date", "created_at", "updated_at",
        )
        read_only_fields = ("id", "last_fired_date", "created_at", "updated_at")

    def validate(self, attrs):
        trigger_type = attrs.get(
            "trigger_type", getattr(self.instance, "trigger_type", None)
        )
        trigger_config = attrs.get(
            "trigger_config",
            getattr(self.instance, "trigger_config", None) or {},
        )
        if not isinstance(trigger_config, dict):
            raise serializers.ValidationError(
                {"trigger_config": "Must be a JSON object."}
            )

        if trigger_type == "daily_nudge":
            raw_time = trigger_config.get("time")
            try:
                dt.time.fromisoformat(str(raw_time))
            except (TypeError, ValueError):
                raise serializers.ValidationError(
                    {"trigger_config": "daily_nudge needs a 'time' as HH:MM."}
                )
            if not isinstance(trigger_config.get("only_if_incomplete", False), bool):
                raise serializers.ValidationError(
                    {"trigger_config": "'only_if_incomplete' must be true or false."}
                )
        elif trigger_type == "streak_reached":
            try:
                streak = int(trigger_config.get("streak"))
            except (TypeError, ValueError):
                raise serializers.ValidationError(
                    {"trigger_config": "streak_reached needs an integer 'streak'."}
                )
            if not 1 <= streak <= 3650:
                raise serializers.ValidationError(
                    {"trigger_config": "'streak' must be between 1 and 3650 days."}
                )

        habit_id = trigger_config.get("habit_id")
        if habit_id is not None:
            if not isinstance(habit_id, int):
                raise serializers.ValidationError(
                    {"trigger_config": "'habit_id' must be an integer habit id."}
                )

        action_config = attrs.get(
            "action_config", getattr(self.instance, "action_config", None) or {}
        )
        if not isinstance(action_config, dict):
            raise serializers.ValidationError(
                {"action_config": "Must be a JSON object."}
            )
        title = action_config.get("title")
        if title is not None and not str(title).strip():
            raise serializers.ValidationError(
                {"action_config": "'title' cannot be blank."}
            )

        # Scope habit/goal ids to the caller so a rule can never watch
        # another user's private data (IDOR guard).
        request = self.context.get("request")
        if request is not None and habit_id is not None and trigger_type in (
            "habit_done", "streak_reached",
        ):
            from habits.models import Habit
            if not Habit.objects.filter(user=request.user, id=habit_id).exists():
                raise serializers.ValidationError(
                    {"trigger_config": "No habit with that id."}
                )
        return attrs


class AutomationRuleToggleSerializer(serializers.Serializer):
    is_active = serializers.BooleanField()
