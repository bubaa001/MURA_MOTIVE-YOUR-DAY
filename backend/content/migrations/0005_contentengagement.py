from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0002_user_avatar"),
        ("content", "0004_contentitem_image"),
    ]

    operations = [
        migrations.CreateModel(
            name="ContentEngagement",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("viewed_at", models.DateTimeField(blank=True, null=True)),
                ("read_at", models.DateTimeField(blank=True, null=True)),
                ("liked", models.BooleanField(default=False)),
                (
                    "item",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="engagements",
                        to="content.contentitem",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="content_engagements",
                        to="accounts.user",
                    ),
                ),
            ],
            options={
                "indexes": [
                    models.Index(fields=["item", "liked"], name="content_con_item_id_29a3e4_idx"),
                    models.Index(fields=["item", "viewed_at"], name="content_con_item_id_0d58fa_idx"),
                ],
                "constraints": [
                    models.UniqueConstraint(
                        fields=("item", "user"),
                        name="unique_content_engagement",
                    )
                ],
            },
        ),
    ]
