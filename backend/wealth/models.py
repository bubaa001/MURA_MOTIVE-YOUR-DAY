from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from django.utils import timezone


class WealthProfile(models.Model):
    """User-level settings for the wealth dashboard."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="wealth_profile",
    )
    currency = models.CharField(max_length=3, default="USD")
    start_date = models.DateField(default=timezone.localdate)
    monthly_expenses = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(0)],
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.user} wealth profile"


class ProfitEntry(models.Model):
    TYPES = [
        ("profit", "Profit"),
        ("loss", "Loss"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profit_entries",
    )
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    date = models.DateField()
    note = models.CharField(max_length=255, blank=True)
    type = models.CharField(max_length=6, choices=TYPES)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-date", "-created_at")

    def __str__(self) -> str:
        return f"{self.get_type_display()}: {self.amount} on {self.date}"


class NetWorthSnapshot(models.Model):
    """A dated net-worth value. A user can keep a history for trend charts."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="net_worth_snapshots",
    )
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    as_of = models.DateField()
    note = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-as_of", "-created_at")
        constraints = [
            models.UniqueConstraint(
                fields=("user", "as_of"),
                name="wealth_networth_user_date_unique",
            ),
        ]

    def __str__(self) -> str:
        return f"{self.user} net worth on {self.as_of}"


class IncomeStream(models.Model):
    FREQUENCIES = [
        ("weekly", "Weekly"),
        ("monthly", "Monthly"),
        ("yearly", "Yearly"),
        ("one_time", "One time"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="income_streams",
    )
    name = models.CharField(max_length=160)
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    frequency = models.CharField(max_length=20, choices=FREQUENCIES, default="monthly")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-is_active", "name", "id")

    def __str__(self) -> str:
        return self.name


class SavingsGoal(models.Model):
    STATUS = [
        ("active", "Active"),
        ("completed", "Completed"),
        ("paused", "Paused"),
        ("cancelled", "Cancelled"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="savings_goals",
    )
    title = models.CharField(max_length=160)
    target_amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0)],
    )
    current_amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(0)],
    )
    target_date = models.DateField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS, default="active", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return self.title
