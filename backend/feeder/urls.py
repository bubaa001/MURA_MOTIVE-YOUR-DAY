from rest_framework.routers import DefaultRouter

from content.views import ContentManageViewSet
from reminders.push_views import PushCampaignViewSet

from . import views

router = DefaultRouter()
router.register("items", views.ExtractedItemViewSet, basename="feeder-item")
# Staff studio: full control over the app's live content hub.
router.register("content", ContentManageViewSet, basename="feeder-content")
# Studio Push: compose + send broadcast notifications via Signo.
router.register("push", PushCampaignViewSet, basename="feeder-push")

urlpatterns = router.urls
