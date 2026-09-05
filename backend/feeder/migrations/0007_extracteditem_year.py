from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("feeder", "0006_extracteditem_image"),
    ]

    operations = [
        migrations.AddField(
            model_name="extracteditem",
            name="year",
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
    ]
