from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

entries_router = DefaultRouter()
entries_router.register("", views.JournalEntryViewSet, basename="journal-entry")

urlpatterns = [
    path("entries/", include(entries_router.urls)),
]
