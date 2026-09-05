"""Create a staff account for TheFeeder without granting superuser access."""
from getpass import getpass

from django.core.exceptions import ValidationError
from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand, CommandError

from accounts.models import User


class Command(BaseCommand):
    help = "Create a staff employee account for TheFeeder."

    def add_arguments(self, parser):
        parser.add_argument("--username", required=True)
        parser.add_argument("--email", default="")
        parser.add_argument("--password", default=None)

    def handle(self, *args, **options):
        username = options["username"]
        if User.objects.filter(username=username).exists():
            raise CommandError(f"User '{username}' already exists.")

        password = options["password"] or getpass("Password: ")
        if not password:
            raise CommandError("Password cannot be empty.")
        if options["password"] is None:
            confirmation = getpass("Password (again): ")
            if password != confirmation:
                raise CommandError("Passwords do not match.")
        try:
            validate_password(password)
        except ValidationError as exc:
            raise CommandError(str(exc)) from exc

        User.objects.create_user(
            username=username,
            email=options["email"],
            password=password,
            is_staff=True,
            is_superuser=False,
        )
        self.stdout.write(self.style.SUCCESS(f"Created Feeder employee '{username}'."))
