from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("content", "0006_contentitem_year"),
    ]

    operations = [
        migrations.AddField(
            model_name="contentengagement",
            name="saved",
            field=models.BooleanField(default=False),
        ),
    ]
