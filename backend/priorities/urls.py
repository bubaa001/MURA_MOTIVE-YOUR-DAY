from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("", views.PriorityViewSet, basename="priority")

urlpatterns = router.urls
