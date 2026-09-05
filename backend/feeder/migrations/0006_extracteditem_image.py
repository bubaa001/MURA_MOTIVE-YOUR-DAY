from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("feeder", "0005_add_motion_quote")]

    operations = [
        migrations.AddField(
            model_name="extracteditem",
            name="image",
            field=models.ImageField(
                blank=True, null=True, upload_to="feeder/items/%Y/%m/"
            ),
        ),
    ]
