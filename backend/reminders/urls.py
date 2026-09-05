from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("", views.ReminderViewSet, basename="reminder")

urlpatterns = router.urls
