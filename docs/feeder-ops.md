# TheFeeder — Operator's Runbook

TheFeeder is the **publishing studio** for MURA. It is the single place where
all app content is written, reviewed, edited, and removed — no Django admin
required. This runbook covers roles, the content lifecycle, how to start
everything, and the daily routine.

## Roles

| Role | Account | Can do |
|---|---|---|
| **Owner** (you) | `buba` (superuser) | Everything: write, review, **publish instantly**, edit live content, archive, restore, delete |
| **Reviewer** | any staff account (`manage.py create_employee`) | Write candidates, review queue (approve/reject), edit text, archive (unpublish), delete. **Cannot force content live** — only the owner publishes |

All studio access requires a staff login. The mobile app itself stays
read-only for content: users read what the studio publishes.

## Content lifecycle

```
Write ──► Review ──► Publish ──► Maintain ──► Retire
 │            │            │            │
 │            │            │            ├─ Edit any field (text/source/year/tags/artwork)
 │            │            │            ├─ Archive  = hidden from the app (reversible)
 │            │            │            └─ Delete   = permanent
 │            │            └─ Sync approved items → Live
 │            └─ pending ── approve / reject
 └─ manual feed: quotes, prayers, philosophies, journal stories,
    motion quotes, words of the day, spiritual insights
```

- **Write**: Feed tab → pick a topic → write it. "Send to review" queues it;
  the owner can also "Publish now" (goes live instantly).
- **Review**: Queue/Review tabs → approve or reject (arrow keys on a focused
  card). Approved items wait for **Sync approved → main app**.
- **Live Content** tab: everything the app shows, with full control:
  search, filter by type/status, select many, then **Archive / Draft /
  Publish / Delete**; or open any item to edit text, source, year, tags,
  artwork (upload or URL). Archived items stay in the studio, hidden from
  the app, and can be restored by the owner.

## Starting everything

**One click:** double-click `MURA-Start.bat` on the desktop (or
`C:\mura\start-mura.bat`). It opens three titled windows — **MURA-Backend**,
**MURA-ngrok**, **MURA-Studio** — and the studio in your browser.
Double-click `MURA-Stop.bat` to shut everything down.

### Option A — Docker (one command, includes ngrok tunnel)

Open `C:\mura` in Docker Desktop and press **Play** on the `mura` project,
or run:

```powershell
cd C:\mura
docker compose up -d --build
```

| Service | Where |
|---|---|
| Backend API | http://localhost:8000/api/v1 |
| **TheFeeder studio** | http://localhost:5175 |
| Public ngrok URL | https://crusader-easing-overlying.ngrok-free.dev (for the phone app) |

### Option B — Local dev (no Docker)

```powershell
# terminal 1 — backend (SQLite works with no .env)
cd C:\mura\backend
.\venv\Scripts\python manage.py migrate
.\venv\Scripts\python manage.py bootstrap_dev
.\venv\Scripts\python manage.py runserver 0.0.0.0:8000

# terminal 2 — TheFeeder studio
cd C:\mura\feeder-web
npm install
npm run dev        # http://localhost:5175

# terminal 3 — optional ngrok tunnel for the phone app
# (token lives in backend/.env — do not commit it)
$env:NGROK_AUTHTOKEN=(Select-String -Path backend\.env -Pattern '^NGROK_AUTHTOKEN=').Line.Split('=')[1]
ngrok http 8000 --url=https://crusader-easing-overlying.ngrok-free.dev
```

## Daily routine (60 seconds)

1. Open TheFeeder → **Queue** — approve or reject anything pending, then hit
   **Sync approved → main app**.
2. Open **Live Content** — search `journal_story` and check nothing is there
   you didn't intend. Archive anything stale, edit anything off, delete junk.
3. Write today's content on the **Feed** tab (owner: "Publish now").
4. Open the phone app → pull to refresh. Done.



## Publishing a new app build (in-app updater)

Every install of the app checks `GET /api/v1/update/` a few seconds after
opening (once per session, with a 24-hour "later" snooze). When a newer build
exists it shows a dialog with the notes; **Update now** downloads the APK and
hands it to the Android installer.

1. Bump the version in `flutter_app/pubspec.yaml` (`version: 1.2.0+3`) and build:
   ```powershell
   cd C:\mura\flutter_app
   flutter build apk --release
   ```
2. Publish it from the backend:
   ```powershell
   cd C:\mura\backend
   .\venv\Scripts\python manage.py publish_release ^
       --apk ..\flutter_app\build\app\outputs\flutter-apk\app-release.apk ^
       --version-name 1.2.0 --version-code 3 ^
       --notes "What's new: ..."
   ```
3. Installed apps detect it on their next open and offer the update.

Notes: the APK is served from the backend over the ngrok tunnel, so the
backend must be running for updates to download. `version-code` must be higher
than what's installed (it comes from the `+N` in pubspec). Remove a release
(`manage.py shell`, delete the `Release`) to stop offering it.

## Safety rules

- **Archive, don't delete** unless you're sure — archiving is reversible.
- The daily quote/prayer/philosophy rotation and the Today motion carousel
  only ever pick from **Live** items, so drafts and archives never leak.
- Exact-duplicate text per type is never created twice (both in the studio
  queue and the app hub).
- Staff accounts can break nothing: they cannot publish live, and nothing is
  deleted without an explicit confirm in the studio.
- The service-key endpoint (`POST /api/v1/content/items/bulk-import/`,
  `X-Service-Key`) is for future automated ingestion and is **disabled**
  until `SERVICE_API_KEY` is set — don't rely on it for daily work.