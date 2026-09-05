from decimal import Decimal

from rest_framework.test import APITestCase

from accounts.models import User
from .models import IncomeStream, NetWorthSnapshot, ProfitEntry, SavingsGoal


class WealthApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="wealth-user", password="strong-pass-123")
        self.other = User.objects.create_user(username="other-wealth-user", password="strong-pass-123")
        self.client.force_authenticate(self.user)

    def test_summary_aggregates_private_wealth_data(self):
        NetWorthSnapshot.objects.create(user=self.user, amount=Decimal("12000.00"), as_of="2026-08-01")
        IncomeStream.objects.create(
            user=self.user, name="Salary", amount=Decimal("6000.00"), frequency="monthly"
        )
        IncomeStream.objects.create(
            user=self.user, name="Side work", amount=Decimal("1200.00"), frequency="yearly"
        )
        SavingsGoal.objects.create(
            user=self.user,
            title="Emergency fund",
            target_amount=Decimal("10000.00"),
            current_amount=Decimal("2500.00"),
        )
        self.client.patch(
            "/api/v1/wealth/profile/", {"monthly_expenses": "2000.00"}, format="json"
        )

        response = self.client.get("/api/v1/wealth/")

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["net_worth"]["amount"], "12000.00")
        self.assertEqual(body["monthly_income"], "6100.00")
        self.assertEqual(body["monthly_expenses"], "2000.00")
        self.assertEqual(body["monthly_savings"], "4100.00")
        self.assertEqual(body["savings_goals"][0]["progress"], 25)

    def test_summary_calculates_journey_profit_and_net_change(self):
        self.client.patch(
            "/api/v1/wealth/profile/",
            {"start_date": "2026-08-10"},
            format="json",
        )
        ProfitEntry.objects.create(
            user=self.user, amount=Decimal("100.00"), date="2026-08-09", type="profit"
        )
        ProfitEntry.objects.create(
            user=self.user, amount=Decimal("350.00"), date="2026-08-12", type="profit"
        )
        ProfitEntry.objects.create(
            user=self.user, amount=Decimal("50.00"), date="2026-08-13", type="loss"
        )

        response = self.client.get("/api/v1/wealth/")

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["journey_start_date"], "2026-08-10")
        self.assertEqual(body["total_profit"], "350.00")
        self.assertEqual(body["total_loss"], "50.00")
        self.assertEqual(body["net_change_since_start"], "300.00")

    def test_profit_entries_are_crud_and_private(self):
        response = self.client.post(
            "/api/v1/wealth/profit-entries/",
            {"amount": "125.50", "date": "2026-08-20", "note": "Freelance", "type": "profit"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.content)
        entry_id = response.json()["id"]
        self.assertEqual(self.client.get("/api/v1/wealth/profit-entries/").status_code, 200)
        self.assertEqual(
            self.client.patch(
                f"/api/v1/wealth/profit-entries/{entry_id}/",
                {"type": "loss"},
                format="json",
            ).json()["type"],
            "loss",
        )
        foreign = ProfitEntry.objects.create(
            user=self.other, amount=Decimal("1.00"), date="2026-08-20", type="profit"
        )
        self.assertEqual(
            self.client.get(f"/api/v1/wealth/profit-entries/{foreign.pk}/").status_code,
            404,
        )

    def test_crud_data_is_scoped_to_authenticated_user(self):
        foreign = IncomeStream.objects.create(
            user=self.other, name="Private", amount=Decimal("1.00"), frequency="monthly"
        )
        response = self.client.get("/api/v1/wealth/income-streams/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["results"], [])
        detail = self.client.get(f"/api/v1/wealth/income-streams/{foreign.pk}/")
        self.assertEqual(detail.status_code, 404)

    def test_savings_goal_rejects_overfunding(self):
        response = self.client.post(
            "/api/v1/wealth/savings-goals/",
            {"title": "House", "target_amount": "100.00", "current_amount": "101.00"},
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("current_amount", response.json())

    def test_net_worth_snapshot_is_unique_per_date(self):
        payload = {"amount": "100.00", "as_of": "2026-08-01"}
        self.assertEqual(self.client.post("/api/v1/wealth/net-worth/", payload, format="json").status_code, 201)
        response = self.client.post("/api/v1/wealth/net-worth/", payload, format="json")
        self.assertEqual(response.status_code, 400)
