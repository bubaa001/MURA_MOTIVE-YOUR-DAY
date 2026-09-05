"""TheFeeder pipeline: write -> review -> approve -> sync.

Book upload / AI extraction was erased. The studio is human-only: the
dashboard writes candidates, a reviewer approves them, and sync_items
publishes approved items into the app's content hub.
"""
from __future__ import annotations


def sync_items(items) -> int:
    """Push approved ExtractedItems into content.ContentItem.

    Dedupe rule matches seed_content: same type + exact text never duplicates.
    Approved items publish straight to the app (status=published). Returns the
    number newly created.
    """
    from content.models import ContentItem

    synced_count = 0
    for item in items:
        target, was_created = ContentItem.objects.get_or_create(
            type=item.type,
            text=item.text,
            defaults={
                "source": item.source,
                "year": item.year,
                "tags": item.tags,
                "status": "published",
                "feeder_item": item,
            },
        )
        if item.image and not target.image:
            target.image = item.image
            target.save(update_fields=("image",))
        if item.image_url and not target.image_url:
            target.image_url = item.image_url
            target.save(update_fields=("image_url",))
        # Attach provenance even for pre-existing duplicates so the studio can
        # always trace where an item came from.
        if target.feeder_item_id is None and not was_created:
            target.feeder_item = item
            target.save(update_fields=("feeder_item",))
        if was_created:
            synced_count += 1
        if not item.synced:
            item.synced = True
            item.save(update_fields=("synced",))
    return synced_count
