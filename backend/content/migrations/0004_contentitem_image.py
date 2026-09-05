from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("content", "0003_add_motion_quote"),
    ]

    operations = [
        migrations.AddField(
            model_name="contentitem",
            name="image",
            field=models.ImageField(blank=True, null=True, upload_to="content/%Y/%m/"),
        ),
    ]
