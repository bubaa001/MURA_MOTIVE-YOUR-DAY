from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("reminders", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="reminder",
            name="last_pushed_date",
            field=models.DateField(blank=True, help_text="Last date this reminder was pushed via Signo (dedup for the push loop).", null=True),
        ),
    ]
