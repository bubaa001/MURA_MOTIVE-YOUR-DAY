from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("habits", "0002_alter_habit_icon"),
    ]

    operations = [
        migrations.AddField(
            model_name="habit",
            name="schedule_days",
            field=models.JSONField(blank=True, default=list),
        ),
    ]
