# MURA — Personal Discipline & Self-Motivation App

A mobile app for daily self-motivation, discipline tracking, and personal growth —
built by Buba as a personal daily-use tool, architected from day one to become a
multi-user product.

**Design language:** "Obsidian & Amber" (see `stitch_zenith_discipline_app_ui/`) —
dark charcoal surfaces, amber-gold energy states, teal reflection states,
Sora + Hanken Grotesk typography, glass cards with soft glows.

## Repository layout

```
product/
├── stitch_zenith_discipline_app_ui/   # UI designs (HTML per screen + DESIGN.md)
├── docs/
│   └── api-contract.md                # Single source of truth for client ↔ server
├── backend/                           # Django 6 + DRF API (PostgreSQL or SQLite)
│   ├── accounts/      # Custom user, JWT auth (/auth/token/, /me/)
│   ├── habits/        # Habit + HabitLog, streak & grace-day engine, heatmap
│   ├── content/       # ContentItem hub: quotes / prayers / philosophies (+admin)
│   ├── wealth/        # Per-user wealth journey and manual financial tracking
│   ├── goals/         # Goals w/ linked habits, progress rings
│   ├── journal/       # JournalEntry ("Posts") + Memory (achievements)
│   ├── priorities/    # Ordered daily focus list
│   └── reminders/     # User-configurable nudges
└── mobile/                            # Expo (React Native) app, expo-router tabs
```

## Screen ↔ route ↔ design mapping

| Design folder | Mobile route | Backend surface |
|---|---|---|
| home_today | `(tabs)/today` | /content/daily/, /habits/today/, /reminders/, heatmap |
| habits_streaks | `(tabs)/habits` | /habits/, /habits/{id}/toggle|history/, /habits/heatmap_data/ |
| daily_priorities | `(tabs)/plan` (segment 1) | /priorities/, /priorities/reorder/ |
| goals_progress | `(tabs)/plan` (segment 2) | /goals/, /goals/{id}/complete/ |
| wealth_builder | `(tabs)/wealth` | /wealth/, /wealth/income-streams/, /wealth/savings-goals/ |
| personal_journal | `(tabs)/journal` | /journal/entries/, /memories/ |
| library_hub | `(tabs)/library` | /content/items/?type=quote\|prayer\|philosophy |
| settings_profile | `settings` (pushed) | /me/, /reminders/ |

The Health section is a filter of the habit engine (`category=physical`), not a
separate system — exactly as specified.

## Quickstart

### Backend URLs

| Environment | URL | Notes |
|---|---|---|
| **Local dev (Django runserver)** | `http://127.0.0.1:8000` | Use for testing locally; admin at `/admin/` |
| **Docker Compose (ngrok tunnel)** | `https://your-ngrok-host.ngrok-free.app` | ngrok URL shown in inspector at `http://localhost:4040`; changes on restart |
| **Production (VPS)** | `https://api.yourdomain.com` | Use your custom domain + TLS certificate (Caddy) |

The **real backend is always at `http://127.0.0.1:8000`** when running Django locally.
The ngrok URL is a temporary public tunnel for testing mobile clients against the dev backend.
For production, configure your VPS domain and use that instead.

### Docker Desktop — one-click startup

Open `C:\mura` in Docker Desktop. The root `docker-compose.yml` is the full
project, so select **mura** and press **Play**. On the first start it builds the
images, starts PostgreSQL, applies migrations, and seeds the local demo account.
Later starts reuse the saved database and uploaded files.

- Feeder dashboard: http://localhost:5175
- Real backend (docker): http://backend:8000 (inside container); `http://127.0.0.1:8000` (host machine)
- ngrok public tunnel: shown at http://localhost:4040/api/tunnels
- ngrok inspector UI: http://localhost:4040
- Initial local login: `buba` / `buba`

Add `GEMINI_API_KEY=...` to `backend/.env` before extracting a book. The API,
database, and Feeder dashboard are included; the Flutter/Expo mobile client is
still run separately on a simulator or phone.

Before starting, copy `backend/.env.example` to `backend/.env` and set
`NGROK_AUTHTOKEN` to the token from the ngrok dashboard. If Docker Desktop does
not list the project yet, run this once from the root:

```powershell
docker compose up --build -d
```

### Backend

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt     # (posix: .venv/bin/pip)
copy .env.example .env                               # optional; SQLite works with no .env
.\.venv\Scripts\python manage.py migrate
.\.venv\Scripts\python manage.py bootstrap_dev       # user buba/buba + seeds content & demo data
.\.venv\Scripts\python manage.py runserver           # http://127.0.0.1:8000
```

- Django admin (content entry from day one): http://127.0.0.1:8000/admin/
- Tests: `.\.venv\Scripts\python manage.py test` (streaks & grace days, toggles, auth flows, content feed, per-user isolation)
- PostgreSQL: set `DB_ENGINE=postgresql` plus `DB_*` vars in `.env`; SQLite is the zero-config fallback.
- Production: `docker compose up --build` (PostgreSQL 17 + migrate + gunicorn) — see `docs/deployment.md`.

### Mobile

```bash
cd flutter_app
flutter run --dart-define=MURA_API_URL=http://127.0.0.1:8000/api/v1
```

**API URL by environment:**
- **Local dev (host machine):** `http://127.0.0.1:8000/api/v1` — run backend with `python manage.py runserver`
- **Local dev (simulator/emulator):** Often `http://10.0.2.2:8000/api/v1` (Android) or `http://localhost:8000/api/v1` (iOS) to reach the host machine's backend
- **Public ngrok tunnel:** `https://your-ngrok-host.ngrok-free.app/api/v1` — find the URL at `http://localhost:4040/api/tunnels`; changes on restart
- **Production VPS:** `https://api.yourdomain.com/api/v1` — use your custom domain with TLS

The free ngrok URL changes after the container restarts. Use an ngrok paid static domain if a stable URL is required.

Sign in with the bootstrapped account (`buba / buba`) or register a new one.

## Architecture decisions (per build spec)

- **Django + DRF** chosen over BaaS because the feedable-content requirement
  (quotes/prayers/philosophies) is a mini-CMS — Django admin provides the content
  management UI for free, registered with `list_filter` and search on text/source.
- **One generic ContentItem model**, not three: new material requires no code change.
- **SimpleJWT** issues tokens; every queryset filters by `request.user`, so Phase 2
  multi-user isolation is already enforced.
- **Streak engine lives in `habits/services.py`**: chronological scan producing
  current/best streaks, rolling-window grace budget, freeze-style covered days,
  pending-today tolerance, 30-day completion rate, GitHub-style heatmap levels.
- **Reminders are user-configurable rows**; Phase 1 schedules local notifications
  in-app, Phase 2 moves scheduling server-side (management command → Expo push API).

## Feeder (Content Admin)

Feeder (`feeder-web/`) is the human publishing studio for all app content —
write → review → sync, plus full control over live content (edit, archive,
restore, delete, artwork). No AI extraction; no Django admin needed for daily
work. See `docs/the-feeder.md` and `docs/feeder-ops.md`.

## Roadmap

- **Phase 1 (this repo):** single-user MVP — auth, habits/streaks, content hub,
  reminders, priorities, goals, journal, memories. ✅
- **Phase 2:** richer multi-user tooling (django-unfold admin), onboarding flow,
  RevenueCat entitlements checked via Django, analytics, Celery-based push.
- Copyright note on seeded content: short excerpts/adaptations only; *The Game of
  Life* (1925) and KJV scripture are public domain, Hill excerpts kept brief by
  design so the corpus stays safe for a paid product later.
