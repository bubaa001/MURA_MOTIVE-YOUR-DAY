"""Mounted by config.urls at /api/v1/memories/."""
from rest_framework.routers import DefaultRouter

from . import views

memory_router = DefaultRouter()
memory_router.register("", views.MemoryViewSet, basename="memory")

urlpatterns = memory_router.urls
