from django.contrib import admin

from .models import IncomeStream, NetWorthSnapshot, ProfitEntry, SavingsGoal, WealthProfile


@admin.register(WealthProfile)
class WealthProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "currency", "monthly_expenses", "updated_at")
    search_fields = ("user__username",)


@admin.register(NetWorthSnapshot)
class NetWorthSnapshotAdmin(admin.ModelAdmin):
    list_display = ("user", "amount", "as_of", "created_at")
    list_filter = ("as_of",)
    search_fields = ("user__username", "note")


@admin.register(ProfitEntry)
class ProfitEntryAdmin(admin.ModelAdmin):
    list_display = ("user", "amount", "type", "date", "note", "created_at")
    list_filter = ("type", "date")
    search_fields = ("user__username", "note")


@admin.register(IncomeStream)
class IncomeStreamAdmin(admin.ModelAdmin):
    list_display = ("name", "user", "amount", "frequency", "is_active")
    list_filter = ("frequency", "is_active")
    search_fields = ("name", "user__username")


@admin.register(SavingsGoal)
class SavingsGoalAdmin(admin.ModelAdmin):
    list_display = ("title", "user", "target_amount", "current_amount", "status", "target_date")
    list_filter = ("status",)
    search_fields = ("title", "user__username")
