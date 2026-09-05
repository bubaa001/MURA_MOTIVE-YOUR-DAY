# MURA Backend

Django 6 + DRF REST API. See the repository root README for architecture context
and `../docs/api-contract.md` for the exact endpoint contract consumed by the app.

## Setup

```bash
python -m venv .venv
.\.venv\Scripts\activate            # posix: source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py bootstrap_dev      # creates buba/buba, seeds content + demo data
python manage.py runserver          # http://127.0.0.1:8000
```

No `.env` is required for local dev (SQLite fallback). Copy `.env.example` to
`.env` for PostgreSQL, secret key, timezone, and host configuration.

## Apps

| App | Models | Highlights |
|---|---|---|
| accounts | User (custom) | JWT auth, register, /me/ profile/avatar patching |
| habits | Habit, HabitLog | Streak engine in services.py (grace days, heatmap), toggle endpoint |
| content | ContentItem | One model for quotes/prayers/philosophies; admin-filtered; deterministic daily rotation |
| wealth | WealthProfile, NetWorthSnapshot, IncomeStream, SavingsGoal, ProfitEntry | Per-user financial dashboard, journey-anchored profit/loss tracking, income streams, savings goals |
| goals | Goal | Linked habits (M2M), progress, complete action |
| journal | JournalEntry, Memory | Mood-tagged posts; memory photos via MEDIA |
| priorities | Priority | Per-day ordered list, bulk reorder endpoint |
| reminders | Reminder | time + weekday list + category, drives local notifications |

## Management commands

- `bootstrap_dev [--username --password --email]` — idempotent dev seeding
  (account, content hub, demo habits/priorities/reminders).
- `create_employee --username <name> --email <email>` — interactively create
  a staff-only Feeder account (no superuser access).
- `seed_content` (via bootstrap_dev) — inserts starter quotes (*Think and Grow
  Rich*, short excerpts), prayers (*The Game of Life* + KJV), and philosophies.

## Streak semantics (habits/services.py)

- Chronological scan over completed days produces current + best streak.
- `grace_days_per_week = g`: up to g missed days inside any rolling 7-day window
  are forgiven; never two consecutive missed days; forgiven days count toward
  streak length (freeze-style).
- An unchecked today is pending — it never breaks a displayed streak.
- Heatmap buckets each day's completion ratio into levels 0–4 for the UI.

## Testing

```bash
python manage.py test
```

Covers toggle behavior, streak math (plain, grace, double-miss, weekly cap),
completion rate, content filtering, daily-feed determinism/idempotent seeding,
wealth aggregation/isolation, and content media serialization.

## Deployment

Production-ready `Dockerfile` (python:3.14-slim + gunicorn, honors $PORT)
and a local `docker-compose.yml` (PostgreSQL 17 + one-shot migrate + web)
live in this directory. The full environment-variable reference,
first-deploy checklist, Railway/Render/Fly.io notes, and the production
security checklist are in [`../docs/deployment.md`](../docs/deployment.md).
