from django.urls import path

from . import views

urlpatterns = [
    path("", views.manifest, name="update-manifest"),
]
