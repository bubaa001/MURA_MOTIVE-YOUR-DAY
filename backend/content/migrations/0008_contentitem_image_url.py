from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0007_contentengagement_saved"),
    ]

    operations = [
        migrations.AddField(
            model_name="contentitem",
            name="image_url",
            field=models.URLField(blank=True),
        ),
    ]
