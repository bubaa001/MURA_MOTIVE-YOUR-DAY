# MURA — API Contract (v1)

Single source of truth between the Django backend (`backend/`) and the Expo app (`mobile/`).

## Conventions

- **Base URL:** `http://127.0.0.1:8000/api/v1` (device/emulator uses host machine LAN IP, e.g. `http://192.168.x.x:8000/api/v1`)
- **Auth:** JWT via `djangorestframework-simplejwt`. Send `Authorization: Bearer <access>`.
- All list endpoints support `?page=` & `?page_size=` pagination (DRF PageNumberPagination, page size 50) unless noted.
- All user-owned data is filtered by `request.user` server-side — the client never sends a user id.
- Dates: ISO-8601 strings (`YYYY-MM-DD` for dates, full timestamps otherwise). Server timezone: local (settings allow config).
- Errors: standard DRF error bodies `{ "detail": "..." }` or `{ "field": ["msg"] }`.

## Auth

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | /auth/token/ | `{username, password}` | → `{access, refresh}` |
| POST | /auth/token/refresh/ | `{refresh}` | → `{access}` |
| POST | /auth/register/ | `{username, email, password}` | creates user, → `{access, refresh}` |
| GET  | /me/ | — | profile: `{id, username, email, first_name, display_name, avatar, date_joined}` |
| PATCH| /me/ | partial profile or multipart `avatar` | e.g. `{display_name}` |
| POST | /me/avatar/ | multipart `avatar` file | replace the authenticated user's avatar |
| DELETE | /me/avatar/ | — | remove the authenticated user's avatar |

## Content hub (Quotes / Prayer / Philosophies) — read-only

One generic model; filter by type.

| Method | Path | Query params | Notes |
|---|---|---|---|
| GET | /content/items/ | `type=quote\|prayer\|philosophy`, `tag=`, `search=`, `source=` | paginated list |
| GET | /content/items/{id}/ | | single item |
| GET    | /content/daily/ | `date=YYYY-MM-DD` (defaults today) | deterministic rotation → `{"date": "...", "quote": {...}|null, "prayer": {...}|null, "philosophy": {...}|null}` — nulls when a type has no items |

ContentItem shape:
```json
{ "id": 1, "type": "quote", "text": "...", "source": "Think and Grow Rich",
  "tags": ["discipline"], "image": "http://127.0.0.1:8000/media/content/2026/02/quote.png",
  "created_at": "2026-02-01T10:00:00Z" }
```
`image` is nullable. Staff can attach an image to a content item in Django
admin; clients receive the media URL in list, detail, and daily-feed responses.
Staff may also `POST` a multipart file under `image` to
`/content/items/{id}/image/`, or `DELETE` that endpoint to remove it.

## Habits & streaks

Habit shape:
```json
{ "id": 1, "name": "Read 10 pages", "description": "", "icon": "menu_book",
  "color": "primary",           // primary | secondary | tertiary | error
  "category": "mental",         // physical | mental | financial | spiritual
  "grace_days_per_week": 1,
  "is_active": true,
  "current_streak": 5,          // computed server-side
  "best_streak": 21,
  "completion_rate_30d": 87,    // percent, computed
  "created_at": "..." }
```

| Method | Path | Notes |
|---|---|---|
| GET    | /habits/ | active habits w/ computed streaks |
| POST   | /habits/ | create |
| GET/PATCH/DELETE | /habits/{id}/ | |
| GET    | /habits/today/ | today's checklist → `{"date": "YYYY-MM-DD", "items": [{habit_id, name, icon, color, category, completed, log_id}]}` |
| POST   | /habits/{id}/toggle/ | body `{"date": "YYYY-MM-DD"}` (optional, default today) → toggles that day's log; returns flat `{habit_id, date, completed, current_streak, best_streak, completion_rate_30d, completed_today}` — `completed` is authoritative for the toggled day; `completed_today` always refers to today |
| GET    | /habits/{id}/history/?days=180 | → `{"days":[{"date":"...","completed":true}], "streaks":{"current":n,"best":m}}` |
| GET    | /habits/heatmap_data/?weeks=26 | → `{"weeks":[{"week_start":"...","days":[{"date":"...","ratio":0.75,"level":3}]}]}` — level = intensity bucket 0..4 of daily completion ratio |

**Streak rules:** a streak counts consecutive covered days. With `grace_days_per_week = g > 0`, up to *g* missed days per rolling 7-day window are forgiven without breaking the streak (never two consecutive missed days); a forgiven day counts toward the streak length (freeze-style). Today with no log yet is "pending", not broken.

## Priorities

Priority shape: `{id, title, category ("Deep Work"|"Health"|"Growth"|"Admin"|custom string), order (int), completed (bool), date ("YYYY-MM-DD", defaults today), created_at}`

| Method | Path | Notes |
|---|---|---|
| GET  | /priorities/?date=YYYY-MM-DD | ordered by `order` |
| POST | /priorities/ | |
| PATCH/DELETE | /priorities/{id}/ | toggle completion via PATCH `{"completed": true}` |
| POST | /priorities/reorder/ | body `{"ordered_ids":[3,1,2]}` → sets `order` field |

## Goals

Goal shape: `{id, title, description, category ("Fitness"|"Mindfulness"|custom), target_date ("YYYY-MM-DD"|null), status ("active"|"achieved"|"abandoned"), progress (int 0-100, manual), linked_habit_ids:[int], created_at}`

| Method | Path | Notes |
|---|---|---|
| GET    | /goals/?status=active | |
| POST   | /goals/ | accepts `linked_habit_ids` |
| GET/PATCH/DELETE | /goals/{id}/ | status transitions via PATCH |
| POST   | /goals/{id}/complete/ | shortcut → `status="achieved"` |

## Wealth

All wealth records are private to the authenticated user. Money values are
returned as decimal strings to avoid floating-point rounding.

| Method | Path | Notes |
|---|---|---|
| GET | /wealth/ | dashboard summary: latest net worth, monthly income/expenses/savings, savings rate, active streams and goals |
| GET/PATCH | /wealth/profile/ | currency (three-letter code), journey `start_date`, and monthly expenses |
| GET/POST | /wealth/net-worth/ | dated net-worth snapshots (`amount`, `as_of`, optional `note`) |
| GET/PATCH/DELETE | /wealth/net-worth/{id}/ | manage a user's snapshot |
| GET/POST | /wealth/income-streams/ | name, amount, frequency (`weekly`, `monthly`, `yearly`, `one_time`), `is_active` |
| GET/PATCH/DELETE | /wealth/income-streams/{id}/ | manage a user's income stream |
| GET/POST | /wealth/savings-goals/ | title, target/current amounts, optional target date, status |
| GET/PATCH/DELETE | /wealth/savings-goals/{id}/ | progress is computed server-side |
| GET/POST | /wealth/profit-entries/ | manual entries with `amount`, `date`, `note`, and `type` (`profit` or `loss`) |
| GET/PATCH/DELETE | /wealth/profit-entries/{id}/ | user-scoped profit/loss entry |

The wealth summary includes `journey_start_date`, gross `total_profit`,
gross `total_loss`, and signed `net_change_since_start`. Profit entries are
manual-only; no card, bank, or financial-account integrations are performed.

## Journal entries ("Posts")

`{id, title, body, mood ("great"|"good"|"neutral"|"low"|null), created_at, updated_at}` — list ordered newest first, supports `?search=`.

CRUD at `/journal/entries/`.

## Memories / Achievements

`{id, title, description, date ("YYYY-MM-DD"), photo (image upload URL or null), created_at}`
Photo upload: multipart `POST /memories/` with `photo` file. List returns absolute URLs.

CRUD at `/memories/`.

## Reminders (user-configurable nudges)

`{id, title, message, time ("HH:MM"), days ([0..6], Mon=0, empty = daily), category ("health"|"mental"|"financial"|"progress"), is_active, created_at}`

CRUD at `/reminders/`. Client schedules local notifications from this list (Phase 2 moves scheduling server-side).

## Health section

Reuses the habits engine: the client filters `GET /habits/` by `category=physical` for the Health view. No separate endpoints in Phase 1.

## CORS

`django-cors-header` allows all origins in dev so the Expo app can call it from any origin.

## Phase 2 hooks (documented, not implemented yet)

- Per-user isolation already enforced by querysets — multi-user ready.
- Server push: management command will scan due reminders and call Expo push API.
- Entitlement checks for subscriptions land on `/me/`.
