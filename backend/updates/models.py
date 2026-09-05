"""Release builds served to the in-app updater.

Buba publishes a freshly built APK here (python manage.py publish_release);
the mobile app checks GET /api/v1/update/ on launch, compares version codes,
and offers to download + install the newer APK.
"""

from django.db import models


class Release(models.Model):
    version_code = models.PositiveIntegerField(unique=True)
    version_name = models.CharField(max_length=50)
    notes = models.TextField(blank=True, help_text="Short changelog shown in the app.")
    apk = models.FileField(upload_to="releases/", help_text="app-release.apk")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ("-version_code",)

    def __str__(self) -> str:
        return f"v{self.version_name} ({self.version_code})"
