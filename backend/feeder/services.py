"""TheFeeder pipeline: write -> review -> approve -> sync.

Book upload / AI extraction was erased. The studio is human-only: the
dashboard writes candidates, a reviewer approves them, and sync_items
publishes approved items into the app's content hub.
"""
from __future__ import annotations

from django.db import transaction


def sync_items(items) -> dict:
    """Push approved ExtractedItems into content.ContentItem.

    Dedupe rule matches seed_content: same type + exact text never duplicates.
    Approved items publish straight to the app (status=published) — callers
    are responsible for the superuser publish gate.

    Returns a per-item report so the studio can show what went live instead
    of a single opaque count.
    """
    from content.models import ContentItem

    report: dict[int, dict] = {}
    for item in items:
        # One savepoint per item: a failure rolls back only that item and the
        # loop continues (without this, the first caught exception would doom
        # the outer transaction).
        try:
            with transaction.atomic():
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
                if not item.synced:
                    item.synced = True
                    item.save(update_fields=("synced",))
            report[item.id] = {
                "content_id": target.id,
                "created": was_created,
                "ok": True,
            }
        except Exception as exc:
            report[item.id] = {"ok": False, "error": str(exc)[:200]}
    return report
