import datetime as dt

from django.db import transaction
from django.utils import timezone
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Priority
from .serializers import PrioritySerializer, ReorderSerializer


class PriorityViewSet(viewsets.ModelViewSet):
    serializer_class = PrioritySerializer

    def get_queryset(self):
        qs = Priority.objects.filter(user=self.request.user)
        raw_date = self.request.query_params.get("date")
        if raw_date:
            try:
                qs = qs.filter(date=dt.date.fromisoformat(raw_date))
            except ValueError:
                pass
        return qs

    def perform_create(self, serializer):
        # New items land at the bottom of their target day's list; a
        # client-supplied date is honored (contract), defaulting to today.
        day = serializer.validated_data.get("date") or timezone.localdate()
        with transaction.atomic():
            # select_for_update closes the race where two simultaneous creates
            # both read the same last.order and duplicate the order number.
            last = (
                Priority.objects.select_for_update()
                .filter(user=self.request.user, date=day)
                .order_by("-order")
                .first()
            )
            serializer.save(user=self.request.user, date=day, order=(last.order + 1) if last else 0)

    @action(detail=False, methods=["post"])
    def reorder(self, request):
        """/priorities/reorder/ {"ordered_ids":[3,1,2]} -> persist drag order."""
        payload = ReorderSerializer(data=request.data)
        payload.is_valid(raise_exception=True)
        ids = payload.validated_data["ordered_ids"]
        items = {
            p.id: p
            for p in Priority.objects.filter(user=request.user, id__in=ids)
        }
        missing = [i for i in ids if i not in items]
        if missing:
            return Response({"detail": f"Unknown priority ids: {missing}"}, status=400)
        # One transaction: a crash mid-loop previously left a day half-reordered.
        with transaction.atomic():
            for index, pid in enumerate(ids):
                items[pid].order = index
                items[pid].save(update_fields=["order"])
        return Response({"reordered": len(ids)})
