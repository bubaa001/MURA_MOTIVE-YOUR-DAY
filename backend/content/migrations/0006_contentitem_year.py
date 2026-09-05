from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0005_contentengagement"),
    ]

    operations = [
        migrations.AddField(
            model_name="contentitem",
            name="year",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
    ]
