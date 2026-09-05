from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Custom user profile used by authentication and the mobile app."""

    display_name = models.CharField(max_length=80, blank=True)
    avatar = models.ImageField(upload_to="avatars/%Y/%m/", null=True, blank=True)

    def __str__(self) -> str:
        return self.get_full_name() or self.display_name or self.username
