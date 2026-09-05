from django.urls import path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("items", views.ContentItemViewSet, basename="content-item")

urlpatterns = [
    path("daily/", views.daily_feed, name="content-daily"),
    path("motion/", views.motion_feed, name="content-motion"),
    # App-to-app ingest for TheFeeder (X-Service-Key auth), registered before
    # the router so "items/bulk-import/" is not shadowed by "items/<pk>/".
    path("items/bulk-import/", views.bulk_import, name="content-bulk-import"),
    *router.urls,
]
