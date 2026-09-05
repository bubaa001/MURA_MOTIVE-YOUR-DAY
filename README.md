# MURA — MOTIVE YOUR DAY

A personal discipline operating system. Daily habits, streaks, focus, content,
and reflection — one app, one backend, one studio you control.

Flutter client. Django REST API. A publishing studio called TheFeeder that owns
every word and image the app shows. No book extraction, no bloat. You write the
content, the app serves it, and updates reach devices from GitHub Releases.

## The system

| Piece | Where | What it does |
|---|---|---|
| App | `flutter_app/` | Flutter client: Today, Habits, Plan, Wealth, Journal, Library. Light + dark. In-app updater. |
| API | `backend/` | Django 6 + DRF. JWT auth, streak engine with grace days, content lifecycle (published/draft/archived), push campaigns. |
| Studio | `feeder-web/` | Write, review, and publish everything the app shows. Live Content manager + broadcast push composer. |
| Updates | GitHub Releases | APK hosted on GitHub; the app checks `/api/v1/update/`, downloads from the release asset, installs. |

## Repo layout

```
flutter_app/                  # the product - Flutter app (v1.2.4+)
backend/                      # Django REST API + TheFeeder engine
feeder-web/                   # TheFeeder studio (React)
docs/                         # api-contract.md, feeder-ops.md, deployment.md
stitch_zenith_discipline_app_ui/   # screen designs (Obsidian & Amber)
```

## Quick start

Backend (SQLite, zero config):

```powershell
cd backend
python -m venv .venv
.\venv\Scripts\pip install -r requirements.txt
.\venv\Scripts\python manage.py migrate
.\venv\Scripts\python manage.py bootstrap_dev   # account buba / buba
.\venv\Scripts\python manage.py runserver
```

App:

```powershell
cd flutter_app
flutter run --dart-define=MURA_API_URL=http://127.0.0.1:8000/api/v1
```

Studio:

```powershell
cd feeder-web
npm install
npm run dev        # http://localhost:5175 - sign in with a staff account
```

## Publishing an app update

```powershell
# bump version in flutter_app/pubspec.yaml, build, then:
$env:GITHUB_TOKEN = "<token>"
python manage.py publish_release ^
    --apk ..\flutter_app\build\app\outputs\flutter-apk\app-release.apk ^
    --version-name 1.3.0 --version-code 8 --notes "what changed" ^
    --github bubaa001/MURA_MOTIVE-YOUR-DAY
```

The APK is uploaded to this repository's Releases. Installed apps see the new
build on their next open and download it from GitHub's CDN.

## Run it in one click

`MURA-Start.bat` starts backend + ngrok + studio. `MURA-Stop.bat` stops them.

## Tests

```powershell
cd backend && .\venv\Scripts\python manage.py test
```

## More

- API contract: `docs/api-contract.md`
- Operator runbook: `docs/feeder-ops.md`
- Design language: `stitch_zenith_discipline_app_ui/obsidian_amber/DESIGN.md`

---

Built by Buba. Personal discipline, product-grade.
