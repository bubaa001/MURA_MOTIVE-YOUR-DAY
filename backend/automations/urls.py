from rest_framework.routers import DefaultRouter

from .views import AutomationRuleViewSet

router = DefaultRouter()
router.register("", AutomationRuleViewSet, basename="automations")

urlpatterns = router.urls
