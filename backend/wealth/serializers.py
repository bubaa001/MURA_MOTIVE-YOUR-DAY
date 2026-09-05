from decimal import Decimal

from rest_framework import serializers

from .models import IncomeStream, NetWorthSnapshot, ProfitEntry, SavingsGoal, WealthProfile


class WealthProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = WealthProfile
        fields = ("currency", "start_date", "monthly_expenses", "updated_at")
        read_only_fields = ("updated_at",)

    def validate_currency(self, value: str) -> str:
        value = value.strip().upper()
        if len(value) != 3 or not value.isalpha():
            raise serializers.ValidationError("Currency must be a three-letter ISO code.")
        return value


class NetWorthSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = NetWorthSnapshot
        fields = ("id", "amount", "as_of", "note", "created_at")
        read_only_fields = ("id", "created_at")

    def validate(self, attrs):
        request = self.context.get("request")
        as_of = attrs.get("as_of", getattr(self.instance, "as_of", None))
        if request is not None and as_of is not None:
            existing = NetWorthSnapshot.objects.filter(user=request.user, as_of=as_of)
            if self.instance is not None:
                existing = existing.exclude(pk=self.instance.pk)
            if existing.exists():
                raise serializers.ValidationError(
                    {"as_of": "A net-worth snapshot already exists for this date."}
                )
        return attrs


class ProfitEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = ProfitEntry
        fields = ("id", "amount", "date", "note", "type", "created_at")
        read_only_fields = ("id", "created_at")


class IncomeStreamSerializer(serializers.ModelSerializer):
    class Meta:
        model = IncomeStream
        fields = ("id", "name", "amount", "frequency", "is_active", "created_at", "updated_at")
        read_only_fields = ("id", "created_at", "updated_at")


class SavingsGoalSerializer(serializers.ModelSerializer):
    progress = serializers.SerializerMethodField()

    class Meta:
        model = SavingsGoal
        fields = (
            "id",
            "title",
            "target_amount",
            "current_amount",
            "target_date",
            "status",
            "progress",
            "created_at",
            "updated_at",
        )
        read_only_fields = ("id", "progress", "created_at", "updated_at")

    def validate(self, attrs):
        target = attrs.get("target_amount", getattr(self.instance, "target_amount", None))
        current = attrs.get("current_amount", getattr(self.instance, "current_amount", Decimal("0")))
        if target is not None and current is not None and current > target:
            raise serializers.ValidationError(
                {"current_amount": "Current amount cannot exceed the target amount."}
            )
        if attrs.get("status") == "completed" and target is not None and current < target:
            raise serializers.ValidationError(
                {"status": "A savings goal can only be completed when it reaches its target."}
            )
        return attrs

    def get_progress(self, obj) -> int:
        if obj.target_amount <= 0:
            return 100 if obj.current_amount >= obj.target_amount else 0
        return min(100, int((obj.current_amount / obj.target_amount) * 100))
