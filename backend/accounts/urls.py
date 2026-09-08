from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .device_views import DeviceTokenViewSet
from .views import AvatarView, MeView

devices_router = DefaultRouter()
devices_router.register("devices", DeviceTokenViewSet, basename="me-devices")

urlpatterns = [
    path("me/", MeView.as_view(), name="me"),
    path("me/avatar/", AvatarView.as_view(), name="me-avatar"),
    path("me/", include(devices_router.urls)),
]
