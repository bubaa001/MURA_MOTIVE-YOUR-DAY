from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("", views.NotificationViewSet, basename="notification-top")

urlpatterns = router.urls
