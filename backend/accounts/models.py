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
    # /me/ and gates premium screens off `plan`; billing providers
    # (RevenueCat/Play Billing) flip this via a webhook later.
    plan = models.CharField(max_length=20, choices=PLANS, default="free")
    # Optional stable id used by a push-notification provider to target
    # this account's devices when per-user topics are enabled.
    push_topic = models.CharField(max_length=150, blank=True)

    class Meta:
        indexes = [
            # Email login lookup: previously an unindexed full-table scan
            # on every sign-in attempt (email__iexact).
            models.Index(fields=("email",), name="accounts_user_email_idx")
        ]

    def __str__(self) -> str:
        return self.get_full_name() or self.display_name or self.username


class DeviceToken(models.Model):
    """One FCM registration token for a device of this account.

    The mobile app registers its Firebase token after sign-in; pushes go
    FCM-first (works on every Android phone, no third-party app needed)
    and fall back to the legacy Signo topic when no device is registered.
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
