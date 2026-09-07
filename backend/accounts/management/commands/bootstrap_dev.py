"""One-shot dev environment setup.

    python manage.py bootstrap_dev            # prints a generated dev password
    python manage.py bootstrap_dev --username me --password s3cret

Creates (or updates) the personal account, seeds starter content, and
installs a small demo set of habits/priorities/reminders so the app has
something to show on first launch.
"""
import datetime as dt
import secrets

from django.core.management import call_command
from django.core.management.base import BaseCommand

from accounts.models import User
from habits.models import Habit, HabitLog
from priorities.models import Priority
from reminders.models import Reminder


class Command(BaseCommand):
    help = "Create the personal account and seed demo data."

    def add_arguments(self, parser):
        parser.add_argument("--username", default="buba")
        # Omit --password to get a generated one (never ship a known default —
        # the old "buba/buba" default leaked into production docs).
        parser.add_argument("--password", default="")
        parser.add_argument("--email", default="buba@mura.local")

    def handle(self, *args, **options):
        user, created = User.objects.get_or_create(
            username=options["username"],
            defaults={
                "email": options["email"],
                "display_name": "Buba",
                # The local bootstrap account is also the Feeder reviewer.
                "is_staff": True,
                "is_superuser": True,
            },
        )
        password = options["password"] or "dev-" + secrets.token_urlsafe(12)
        if created:
            user.set_password(password)
            user.save()
            self.stdout.write(self.style.SUCCESS(f"Created user '{user.username}' (password: {password})."))
        else:
            # Existing local demo databases created by an earlier version need
            # the same access level for the staff-only Feeder dashboard.
            if not user.is_staff or not user.is_superuser:
                user.is_staff = True
                user.is_superuser = True
                user.save(update_fields=("is_staff", "is_superuser"))
            self.stdout.write(f"User '{user.username}' already exists.")

        call_command("seed_content", verbosity=0)
        self.stdout.write(self.style.SUCCESS("Content hub seeded."))

        if not user.habits.exists():
            habits = {
                "physical": ("Morning Workout", "fitness_center", "primary"),
                "mental": ("Read 10 Pages", "menu_book", "tertiary"),
                "financial": ("Track Spending", "payments", "secondary"),
                "spiritual": ("Prayer & Reflection", "self_improvement", "secondary"),
                "physical": ("Drink Water", "water_drop", "error"),
            }
            for category, (name, icon, color) in habits.items():
                habit = Habit.objects.create(
                    user=user, name=name, icon=icon, color=color, category=category,
                    grace_days_per_week=1,
                )
                HabitLog.objects.create(habit=habit, date=dt.date.today(), completed=True)
            self.stdout.write(self.style.SUCCESS("Demo habits installed."))

        if not user.priorities.exists():
            for order, (title, cat) in enumerate([
                ("Finalize Q3 strategy deck", "Deep Work"),
                ("45min Zone 2 cardio", "Health"),
                ("Read 20 pages", "Growth"),
                ("Clear inbox to zero", "Admin"),
            ]):
                Priority.objects.create(user=user, title=title, category=cat, order=order)
            self.stdout.write(self.style.SUCCESS("Demo priorities installed."))

        if not user.reminders.exists():
            Reminder.objects.create(user=user, title="Morning Routine", message="Own the first hour.", time=dt.time(6, 30), category="mental")
            Reminder.objects.create(user=user, title="Hydration Break", time=dt.time(11, 0), category="health")
            Reminder.objects.create(user=user, title="Evening Reflection", message="Journal three lines.", time=dt.time(21, 0), category="progress", is_active=True)
            self.stdout.write(self.style.SUCCESS("Demo reminders installed."))
