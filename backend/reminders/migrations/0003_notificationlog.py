from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("reminders", "0002_reminder_last_pushed_date"),
    ]

    operations = [
        migrations.CreateModel(
            name="NotificationLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("title", models.CharField(max_length=120)),
                ("body", models.CharField(blank=True, max_length=280)),
                ("kind", models.CharField(blank=True, choices=[("reminder", "Reminder"), ("streak_milestone", "Streak milestone"), ("goal_achieved", "Goal achieved"), ("general", "General")], default="general", max_length=20)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("read_at", models.DateTimeField(null=True, blank=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="notifications", to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "ordering": ("-created_at",),
            },
        ),
    ]
