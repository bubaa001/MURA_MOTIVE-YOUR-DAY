from rest_framework import serializers

from .models import Priority


class PrioritySerializer(serializers.ModelSerializer):
    class Meta:
        model = Priority
        fields = ("id", "title", "category", "order", "completed", "date", "created_at")
        read_only_fields = ("id", "order", "created_at")


class ReorderSerializer(serializers.Serializer):
    ordered_ids = serializers.ListField(
        child=serializers.IntegerField(), allow_empty=False
    )
