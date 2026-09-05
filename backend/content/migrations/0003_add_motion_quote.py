from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0002_alter_contentitem_type"),
    ]

    operations = [
        migrations.AlterField(
            model_name="contentitem",
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
                db_index=True,
                max_length=30,
            ),
        ),
    ]
