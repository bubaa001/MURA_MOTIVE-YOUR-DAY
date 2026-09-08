from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Custom user profile used by authentication and the mobile app."""

    PLANS = [
        ("free", "Free"),
        ("premium", "Premium"),
    ]

    display_name = models.CharField(max_length=80, blank=True)
    avatar = models.ImageField(upload_to="avatars/%Y/%m/", null=True, blank=True)
    # Monetization: entitlement source of truth. The mobile app reads
    # /me/ and gates premium screens off `plan`; promo codes (and, later,
    # RevenueCat/Play Billing webhooks) flip this.
    plan = models.CharField(max_length=20, choices=PLANS, default="free")
    # When the current premium period ends (promo codes set this; null =
    # free forever or never expiring premium).
    plan_expires_at = models.DateField(null=True, blank=True)
    # Optional stable id used by a push-notification provider to target
    # this account's devices when per-user topics are enabled.
    push_topic = models.CharField(max_length=150, blank=True)

    class Meta:
        indexes = [
            # Email login lookup: previously an unindexed full-table scan
            # on every sign-in attempt (email__iexact).
            models.Index(fields=("email",), name="accounts_user_email_idx")
        ]

    @property
    def effective_plan(self) -> str:
        """Plan the client should see: premium only while not expired."""
        if self.plan == "premium" and self.plan_expires_at:
            from django.utils import timezone
            if timezone.localdate() > self.plan_expires_at:
                return "free"
        return self.plan

    def __str__(self) -> str:
        return self.get_full_name() or self.display_name or self.username


class PromoCode(models.Model):
    """One-time upgrade code the owner sells or gifts.

    Revenue flow without app-store billing: the buyer pays via the
    owner's PREMIUM_PAYMENT_URL (PayPal etc.), the owner generates codes
    (manage.py make_promo_codes) and hands one over; the buyer redeems it
    in the app (POST /me/redeem/) and premium activates.
    """

    code = models.CharField(max_length=24, unique=True)
    days = models.PositiveIntegerField(
        help_text="Premium days granted. Use 36500 for a lifetime code."
    )
    is_active = models.BooleanField(default=True)
    redeemed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="redeemed_promo_codes",
    )
    redeemed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f"{self.code} ({self.days}d{' — used' if self.redeemed_by else ''})"


class DeviceToken(models.Model):
    """One FCM registration token for a device of this account.

    The mobile app registers its Firebase token after sign-in; pushes go
    to every registered device via FCM (Google) — MURA's own push
    channel, no third-party app needed.
    """

    PLATFORMS = [
        ("android", "Android"),
        ("ios", "iOS"),
        ("web", "Web"),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="devices",
    )
    token = models.CharField(max_length=512, unique=True)
    platform = models.CharField(max_length=10, choices=PLATFORMS, default="android")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.platform} device of {self.user_id} ({self.token[:12]}…)"
