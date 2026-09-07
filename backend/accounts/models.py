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
