# TheFeeder — MURA publishing studio

Internal, web-based studio for everything the MURA app shows. Content is
written by humans, reviewed, approved, and synced into the app's
`ContentItem` hub — **no AI, no book extraction** (that feature was erased).
Lives inside the main Django backend as the `feeder` app plus a small React
dashboard in `feeder-web/`.

## Loop

1. **Write** — the Feed tab: pick a topic (quote, prayer, philosophy, word of
   the day, journal story, motion quote, spiritual insight), write it, and
   "Send to review". The owner can also "Publish now" to skip the queue.
2. **Review** — the Queue tab: approve or reject candidates (left arrow =
   reject · right arrow = approve, or "Approve all shown").
3. **Sync** — "Sync approved → main app" publishes approved items into the
   app hub (exact-text dedupe; provenance recorded).
4. **Maintain** — the **Live Content** tab loads everything in the app's
   database: search, filter, select many, then archive / draft / publish /
   delete, or open any item to edit text, source, year, tags, and artwork
   (upload or URL). Archived items are hidden from the app; deletes are
   permanent.

## Run it

Backend (from `backend/`):

    .venv\Scripts\python.exe manage.py runserver

Frontend (from `feeder-web/`, second terminal):

    npm install
    npm run dev        # http://localhost:5175 (proxies /api + /media to :8000)

Sign in with a **staff** Django account (the API is staff-only). Only the
owner (superuser) can publish instantly; reviewers edit/archive/delete but
never force content live. Django admin at `/admin/` remains a fallback.

## Environment (backend/.env)

| Variable         | Purpose                                                       |
|------------------|---------------------------------------------------------------|
| SERVICE_API_KEY  | Enables POST /api/v1/content/items/bulk-import/ (X-Service-Key); disabled when unset |

## HTTP surface (all staff-only unless noted)

- `GET /api/v1/feeder/items/?review_status=&type=` — the review queue
- `POST /api/v1/feeder/items/manual-submit/` — submit `{type, text, source?, year?, tags?, image?}` to pending review
- `POST /api/v1/feeder/items/bulk-review/` — `{ids, review_status}`
- `POST /api/v1/feeder/items/sync/` — push approved+unsynced into ContentItem
- `GET/POST/PATCH/DELETE /api/v1/feeder/content/` — live content hub management
- `POST /api/v1/feeder/content/bulk/` — `{ids, action: archive|restore|draft|delete}`
- `POST/DELETE /api/v1/feeder/content/{id}/image/` — artwork upload/remove
- `POST /api/v1/content/items/bulk-import/` — service-key ingest (app-to-app; disabled until SERVICE_API_KEY is set)

CLI alternative to the sync button:

    python manage.py sync_approved_items

See `docs/feeder-ops.md` for the operator's runbook.
