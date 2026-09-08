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
| POST | /auth/token/ | `{username, password}` | → `{access, refresh}`; accepts email as identifier (prefers exact username match). Throttled 30/min |
| POST | /auth/token/refresh/ | `{refresh}` | → `{access}` |
| POST | /auth/register/ | `{username, email, password}` | creates user, → `{access, refresh}` |
| POST | /auth/register/employee/ | `{username, email, password, signup_key}` | staff (feeder) account — 400 without the owner's `EMPLOYEE_SIGNUP_KEY`; disabled entirely when the env var is unset |
| GET  | /me/ | — | profile: `{id, username, email, first_name, display_name, avatar, date_joined, is_staff, is_superuser, plan, push_topic}` — `plan` (`free`\|`premium`) is the monetization entitlement source of truth |
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
| GET | /content/motion/ | `date=YYYY-MM-DD` | the day's Motion Quotes batch → `{"date", "count", "items"}`; size set in the feeder (`/feeder/settings/` `motion_quote_count`, default 10), reshuffled every day but stable for the whole day |

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
| GET    | /habits/history_batch/?days=180 | ALL habits' history in one call → `{"days_span":180,"habits":{"<habit_id>":{"days":[...],"streaks":{"current":n,"best":m}}}}` — replaces the per-habit loop; the mobile app must use this |
| GET    | /habits/heatmap_data/?weeks=26 | → `{"weeks":[{"week_start":"...","days":[{"date":"...","ratio":0.75,"level":3}]}]}` — level = intensity bucket 0..4 of daily completion ratio |

**All date math is timezone-aware** (uses `TIMEZONE` from `.env`, default UTC; prod uses America/New_York). Toggling a future date returns 400.

**Pagination:** every list endpoint returns DRF pages `{count, next, previous, results}` (page_size 50, max 200). Clients that need full lists MUST follow `next` (absolute URL) — reading only `results` silently truncates at the first page.

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

## Notification feed (in-app)

`{id, title, body, kind ("reminder"|"habit"|"goal_achieved"|"streak"|"campaign"|"automation"|"general"), created_at, read_at}` at `/notifications/` (user-scoped, newest first).

| Method | Path | Notes |
|---|---|---|
| POST | /notifications/read_all/ | mark everything read (clears the unread badge) |
| DELETE (or POST) | /notifications/clear/ | empty the feed; `?read_only=1` keeps unread items |

## Push devices (FCM token registration)

`{id, token, platform ("android"|"ios"|"web"), is_active, created_at}`

| Method | Path | Notes |
|---|---|---|
| POST | /me/devices/ | `{token, platform}` — idempotent upsert: re-POSTing a known token refreshes/reactivates its row (safe on app restart, reinstall, token rotation) |
| GET | /me/devices/ | list the caller's active devices |
| DELETE | /me/devices/{id}/ | soft-deactivates one device (pushes stop; row kept so a future re-sign-in is still an update) |

Deleting marks `is_active=false` rather than dropping the row — the unique token constraint means a hard delete would race a concurrent re-register.

## Automations (user-defined WHEN → THEN rules)

`{id, name, trigger_type, trigger_config, action_type, action_config, is_active, last_fired_date, created_at, updated_at}`

CRUD at `/automations/` (user-scoped). `POST /automations/{id}/toggle/` flips `is_active`.

Trigger types + config:
- `habit_done` — `{habit_id?: int}` (omit = any habit); fires on completion
- `all_habits_done` — `{}`; fires when the day's checklist clears
- `streak_reached` — `{streak: int, habit_id?: int}`; fires exactly at N (once per day per rule)
- `goal_achieved` — `{goal_id?: int}`; fires once per goal (double-complete is a no-op)
- `daily_nudge` — `{time: "HH:MM", only_if_incomplete: bool}`; evaluated hourly by `manage.py run_automations` (2h catch-up window, same-day dedup)

Action `push` config: `{title, body}` — `{habit}`, `{streak}`, `{goal}` placeholders render real values. Every fire writes an in-app `NotificationLog` (kind `automation`) plus a push via FCM (Signo fallback when the user has no registered device).

Config validation: unknown `habit_id` (404-style) and malformed `time`/`streak` are 400s; habit ids are scoped to the caller (another user's id is rejected as "no habit with that id").

## TheFeeder (staff studio — all endpoints require is_staff)

| Method | Path | Notes |
|---|---|---|
| GET/POST/PATCH/DELETE | /feeder/items/ | review queue CRUD; `?review_status=pending&type=quote`; PATCH accepts `type, text, source, year, tags, image_url, review_status, note` (candidates ARE editable) |
| POST | /feeder/items/manual-submit/ | new pending candidate (records `submitted_by`) |
| POST | /feeder/items/bulk-review/ | `{ids, review_status}` — records `reviewed_by/at` |
| POST | /feeder/items/sync/ | **superuser only** (403 for staff) — publishes all approved+unsynced; → `{submitted, synced, results:[{item_id, content_id, created, ok, error?}]}` |
| POST | /feeder/items/{id}/sync_item/ | **superuser only** — publish exactly one approved candidate |
| POST | /feeder/items/{id}/unsync/ | **superuser only** — reset `synced` so a deleted live copy can be re-synced |
| GET/POST/PATCH/DELETE | /feeder/content/ | live content hub CRUD (publish status changes: superuser only) |
| GET/POST/PATCH/DELETE | /feeder/push/ | FCM broadcast campaigns; `send`/`test` actions |
| GET/PUT | /feeder/settings/ | studio-tunable app settings; currently `motion_quote_count` (1–50, default 10) — how many motion quotes the app's Today feed shows per day |

## Health section

Reuses the habits engine: the client filters `GET /habits/` by `category=physical` for the Health view. No separate endpoints in Phase 1.

## CORS

`django-cors-header` allows all origins in dev so the studio/app can call it from any origin; production sets `CORS_ALLOW_ALL=false`.

## Push architecture

All pushes go through Google FCM (see `docs/runbook.md` §5): the app registers its device token at `/me/devices/` after sign-in; automations, reminders, campaigns and release announcements send through the FCM HTTP v1 API. The in-app `/notifications/` feed is the guaranteed channel and records every event.

## Phase 2 hooks

- Entitlement checks for subscriptions land on `/me/` — `User.plan` field is live; RevenueCat webhook flips it (runbook §7).
- Server-side reminder pushes run via scheduled `push_due_reminders` (due-window match, hourly-safe).
