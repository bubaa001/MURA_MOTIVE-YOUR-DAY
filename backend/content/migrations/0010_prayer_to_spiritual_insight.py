"""Convert legacy 'prayer' content to 'spiritual_insight'.

Buba writes no prayers: the prayer slot in the daily feed was replaced by
spiritual insight, so existing prayer items are retyped (deduped per
(type, text)) so nothing is lost from the app.
"""
from django.db import migrations


def forwards(apps, schema_editor):
    ContentItem = apps.get_model("content", "ContentItem")
    moved = 0
    for item in ContentItem.objects.filter(type="prayer").order_by("id"):
        if not ContentItem.objects.filter(
            type="spiritual_insight", text=item.text
        ).exists():
            item.type = "spiritual_insight"
            item.save(update_fields=("type",))
            moved += 1
        else:
            item.delete()
    if moved:
        print(f"  retyped {moved} prayer items -> spiritual_insight")


def backwards(apps, schema_editor):
    # One-way retype; original prayer rows are not recovered.
    pass


class Migration(migrations.Migration):
    dependencies = [("content", "0009_contentitem_feeder_item_contentitem_status_and_more")]
    operations = [migrations.RunPython(forwards, backwards)]
