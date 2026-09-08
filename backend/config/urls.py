"""Root URL configuration — everything the mobile app consumes lives under /api/v1/."""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from django.views.static import serve

api_v1 = [
    # Auth + profile -> /auth/token/, /auth/token/refresh/, /auth/register/, /me/
    path("auth/", include("accounts.auth_urls")),
    path("", include("accounts.urls")),
    # Content hub: /content/items/, /content/daily/
    path("content/", include("content.urls")),
    # Habits engine: /habits/, /habits/today/, /habits/{id}/toggle/ ...
    path("habits/", include("habits.urls")),
    # Goals
    path("goals/", include("goals.urls")),
    # Wealth tracking
    path("wealth/", include("wealth.urls")),
    # Journal entries + memories
    path("journal/", include("journal.urls")),
    path("memories/", include("journal.memory_urls")),
    # Priorities (+ /priorities/reorder/)
    path("priorities/", include("priorities.urls")),
    # Reminders
    path("reminders/", include("reminders.urls")),
    # User-defined rules: WHEN trigger THEN notify (/automations/)
    path("automations/", include("automations.urls")),
    # Notification feed (in-app): /notifications/, /notifications/read_all/
    path("notifications/", include("reminders.notification_urls")),
    # TheFeeder: book upload/extraction/review/sync (staff-only, React dashboard)
    path("feeder/", include("feeder.urls")),
    # In-app updater manifest: GET /update/
    path("update/", include("updates.urls")),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include(api_v1)),
]

# The local deployment serves user-uploaded artwork and avatars through Django.
# Production deployments should serve this path from the media storage layer.
urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
if not settings.DEBUG:
    urlpatterns += [
        path("media/<path:path>", serve, {"document_root": settings.MEDIA_ROOT}),
    ]
