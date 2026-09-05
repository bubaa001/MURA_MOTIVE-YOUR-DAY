# TheFeeder — MURA publishing studio (current state)

> Supersedes the old "AI Content Extraction & Ingestion Engine" design. Book
> upload and AI extraction were **erased** (per product decision): TheFeeder is
> now a human-only publishing studio.

TheFeeder is the single place where all MURA app content is written,
reviewed, edited, archived, and removed — no Django admin required.

- **Write** — manual feed for all 7 content types (quote, motion quote,
  prayer, philosophy, word of the day, journal story, spiritual insight).
- **Review** — pending queue: approve / reject, then sync approved items live.
- **Live Content** — full control over everything in the app's database:
  load, search, select, edit (text/source/year/tags/artwork), archive,
  restore, delete.

See:
- `docs/the-feeder.md` — architecture, run commands, HTTP surface
- `docs/feeder-ops.md` — operator runbook (roles, lifecycle, daily routine)
- `feeder-web/` — the React dashboard
