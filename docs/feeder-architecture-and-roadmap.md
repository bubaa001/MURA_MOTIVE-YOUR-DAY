# TheFeeder — Architecture & Roadmap (current state)

> Superseded: the AI extraction architecture described in earlier versions was
> **erased**. TheFeeder is a human-only publishing studio. See
> `docs/the-feeder.md` and `docs/feeder-ops.md`.

## Current architecture

1. **Write** — `feeder-web` manual feed for all 7 content types.
2. **Review Hub** — `ExtractedItem` pending queue; batch approve/reject
   (`POST /api/v1/feeder/items/bulk-review/`).
3. **Sync Service** — `sync_items` publishes approved items into
   `ContentItem` (status=published, provenance recorded, exact-text dedupe).
4. **Live Content Management** — staff-only CRUD over the whole content hub
   (`/api/v1/feeder/content/`): edit every field, archive/restore/delete,
   upload artwork, bulk actions.

## Roadmap

- [x] Human content studio (write → review → sync)
- [x] Live content manager (load, edit, archive, restore, delete)
- [x] Staff-only security on every studio endpoint
- [x] Provenance tracing (which candidate produced each live item)
- [ ] Swipeable review card UI
- [ ] Scheduled ingestion from curated RSS feeds (manual approval still enforced)
