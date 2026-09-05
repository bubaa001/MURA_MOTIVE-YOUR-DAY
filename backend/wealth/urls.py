from django.urls import include, path
from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register("net-worth", views.NetWorthSnapshotViewSet, basename="net-worth")
router.register("net-worths", views.NetWorthSnapshotViewSet, basename="net-worths")
router.register("profit-entries", views.ProfitEntryViewSet, basename="profit-entry")
router.register("income-streams", views.IncomeStreamViewSet, basename="income-stream")
router.register("savings-goals", views.SavingsGoalViewSet, basename="savings-goal")

urlpatterns = [
    path("", views.wealth_summary, name="wealth-summary"),
    path("profile/", views.WealthProfileView.as_view(), name="wealth-profile"),
    *router.urls,
]
