from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("goals", "0001_initial")]

    operations = [
        migrations.AddField(
            model_name="goal",
            name="goal_type",
            field=models.CharField(
                choices=[
                    ("chief_aim", "Definite chief aim"),
                    ("economic", "Economic"),
                    ("things", "Things"),
                    ("personal_development", "Personal development"),
                ],
                default="personal_development",
                max_length=30,
            ),
        ),
        migrations.AddField(
            model_name="goal",
            name="horizon",
            field=models.CharField(
                choices=[("short", "Short range"), ("long", "Long range")],
                default="short",
                max_length=10,
            ),
        ),
    ]
