from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("feeder", "0004_feedersettings_delete_feederconfig"),
    ]

    operations = [
        migrations.AlterField(
            model_name="extracteditem",
            name="type",
            field=models.CharField(
                choices=[
                    ("quote", "Quote"),
                    ("motion_quote", "Motion Quote"),
                    ("prayer", "Prayer"),
                    ("philosophy", "Philosophy"),
                    ("word_of_the_day", "Word of the Day"),
                    ("journal_story", "Journal Story"),
                    ("spiritual_insight", "Spiritual Insight"),
                ],
                max_length=30,
            ),
        ),
    ]
