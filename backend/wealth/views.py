from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Q, QuerySet, Sum
from django.utils import timezone
from rest_framework import generics, serializers, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .models import IncomeStream, NetWorthSnapshot, ProfitEntry, SavingsGoal, WealthProfile
from .serializers import (
    IncomeStreamSerializer,
    NetWorthSnapshotSerializer,
    ProfitEntrySerializer,
    SavingsGoalSerializer,
    WealthProfileSerializer,
)


def _get_or_create_profile(user) -> WealthProfile:
    """Concurrent first loads previously raced the OneToOne insert and
    surfaced IntegrityError as a 500; retry the fetch instead."""
    try:
        with transaction.atomic():
            profile, _created = WealthProfile.objects.get_or_create(user=user)
    except IntegrityError:
        profile = WealthProfile.objects.get(user=user)
    return profile


def _monthly_income(streams: QuerySet[IncomeStream]) -> Decimal:
    total = Decimal("0")
    for stream in streams.filter(is_active=True):
        if stream.frequency == "weekly":
            total += stream.amount * Decimal("52") / Decimal("12")
        elif stream.frequency == "yearly":
            total += stream.amount / Decimal("12")
        elif stream.frequency == "monthly":
            total += stream.amount
    return total.quantize(Decimal("0.01"))


class UserOwnedViewSet(viewsets.ModelViewSet):
    permission_classes = (IsAuthenticated,)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)


class NetWorthSnapshotViewSet(UserOwnedViewSet):
    serializer_class = NetWorthSnapshotSerializer

    def get_queryset(self):
        return NetWorthSnapshot.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        # The serializer's duplicate-date check is check-then-act; the DB
        # unique constraint is the real guard — surface its race as a 400.
        try:
            with transaction.atomic():
                serializer.save(user=self.request.user)
        except IntegrityError:
            raise serializers.ValidationError(
                {"as_of": "A net-worth snapshot already exists for this date."}
            )


class ProfitEntryViewSet(UserOwnedViewSet):
    serializer_class = ProfitEntrySerializer

    def get_queryset(self):
        return ProfitEntry.objects.filter(user=self.request.user)


class IncomeStreamViewSet(UserOwnedViewSet):
    serializer_class = IncomeStreamSerializer

    def get_queryset(self):
        return IncomeStream.objects.filter(user=self.request.user)


class SavingsGoalViewSet(UserOwnedViewSet):
    serializer_class = SavingsGoalSerializer

    def get_queryset(self):
        qs = SavingsGoal.objects.filter(user=self.request.user)
        status_param = self.request.query_params.get("status")
        return qs.filter(status=status_param) if status_param else qs


class WealthProfileView(generics.RetrieveUpdateAPIView):
    serializer_class = WealthProfileSerializer
    permission_classes = (IsAuthenticated,)

    def get_object(self):
        return _get_or_create_profile(self.request.user)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def wealth_summary(request):
    """Return the current dashboard values without exposing another user."""
    snapshots = NetWorthSnapshot.objects.filter(user=request.user)
    latest = snapshots.first()
    previous = snapshots[1] if snapshots.count() > 1 else None
    streams = IncomeStream.objects.filter(user=request.user)
    profile = _get_or_create_profile(request.user)
    goals = SavingsGoal.objects.filter(user=request.user, status="active")
    entries = ProfitEntry.objects.filter(user=request.user, date__gte=profile.start_date)
    totals = entries.aggregate(
        profit=Sum("amount", filter=Q(type="profit")),
        loss=Sum("amount", filter=Q(type="loss")),
    )
    total_profit = totals["profit"] or Decimal("0")
    total_loss = totals["loss"] or Decimal("0")
    net_change = (total_profit - total_loss).quantize(Decimal("0.01"))
    months_since_start = max(
        Decimal("1"),
        Decimal(
            (timezone.localdate().year - profile.start_date.year) * 12
            + timezone.localdate().month
            - profile.start_date.month
            + 1
        ),
    )
    monthly_income = _monthly_income(streams)
    monthly_savings = monthly_income - profile.monthly_expenses
    savings_rate = (
        (monthly_savings / monthly_income * Decimal("100")).quantize(Decimal("0.01"))
        if monthly_income
        else Decimal("0")
    )
    net_profit_margin = (
        (net_change / monthly_income * Decimal("100")).quantize(Decimal("0.01"))
        if monthly_income
        else Decimal("0")
    )
    expense_ratio = (
        (profile.monthly_expenses / monthly_income * Decimal("100")).quantize(Decimal("0.01"))
        if monthly_income
        else Decimal("0")
    )

    def money(value):
        return f"{value:.2f}" if value is not None else None

    return Response(
        {
            "currency": profile.currency,
            "journey_start_date": profile.start_date,
            "total_profit": money(total_profit),
            "total_loss": money(total_loss),
            "net_change_since_start": money(net_change),
            "average_monthly_profit": money(net_change / months_since_start),
            "net_profit_margin": money(net_profit_margin),
            "expense_ratio": money(expense_ratio),
            "months_since_start": int(months_since_start),
            "net_worth": NetWorthSnapshotSerializer(latest, context={"request": request}).data
            if latest
            else None,
            "net_worth_change": (
                money((latest.amount - previous.amount).quantize(Decimal("0.01")))
                if latest and previous
                else None
            ),
            "monthly_income": money(monthly_income),
            "monthly_expenses": money(profile.monthly_expenses),
            "monthly_savings": money(monthly_savings),
            "savings_rate": money(savings_rate),
            "income_streams": IncomeStreamSerializer(
                streams, many=True, context={"request": request}
            ).data,
            "profit_entries": ProfitEntrySerializer(
                entries[:25], many=True, context={"request": request}
            ).data,
            "net_worth_history": NetWorthSnapshotSerializer(
                snapshots[:12], many=True, context={"request": request}
            ).data,
            "savings_goals": SavingsGoalSerializer(
                goals, many=True, context={"request": request}
            ).data,
        }
    )
