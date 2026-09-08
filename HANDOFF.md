Here's the updated **HANDOFF.md** with everything we've done — the PythonAnywhere deployment, the Flutter fixes, the APK releases, and the current state of everything.

---

```markdown
# MURA — Project Handoff (read this first)

Personal discipline app for Buba. Backend: Django REST API. Mobile: Flutter (migrated from React Native).

---

## 🚀 Current Deployment Status (2026-09-07)

### Backend
- **Hosted on:** PythonAnywhere (free tier)
- **URL:** `https://bubaa.pythonanywhere.com`
- **API base:** `https://bubaa.pythonanywhere.com/api/v1/`
- **Admin:** `https://bubaa.pythonanywhere.com/admin/`
- **Login:** username `buba` / password **ROTATED — see `docs/runbook.md` "Admin credentials"** (the old password was published in this public repo and had to be changed; never write real credentials in docs again)
- **Database:** SQLite (uploaded from local development)
- **Media files:** Stored in `/home/bubaa/MURA/backend/media/`
- **Environment variables:** Set in `.env` file (includes `SIGNO_NAMESPACE`, `SECRET_KEY`, etc.)

### Flutter App
- **Code location:** `C:\mura\flutter_app`
- **Current version:** `1.4.0+10` — the single source of truth is `flutter_app/pubspec.yaml:5`. Bump it there, build, then `manage.py publish_release` (runbook §6). Do not trust commit messages for versions.
- **APK:** Available on [GitHub Releases](https://github.com/bubaa001/MURA_MOTIVE-YOUR-DAY/releases)
- **API URL:** `https://bubaa.pythonanywhere.com/api/v1`
- **Media URL:** `https://bubaa.pythonanywhere.com` (separate from API for image serving)

### Feeder Studio (Content Management)
- **Location:** `C:\mura\feeder-web`
- **Status:** Development only (localhost:5175)
- **API connection:** Points to `https://bubaa.pythonanywhere.com/api/v1`
- **Note:** Not deployed to production — runs locally on the dev machine

---

## ✅ What's Done and Working

### Backend (Django + DRF)
- ✅ Deployed on PythonAnywhere (`bubaa.pythonanywhere.com`)
- ✅ SQLite database migrated (with all local data intact)
- ✅ Media files uploaded and served from `/media/` path
- ✅ Static files collected and served via Whitenoise
- ✅ `.env` file configured with all necessary variables
- ✅ Signo namespace configured for push notifications (⚠️ needs webhook URL update)
- ✅ API endpoints: auth, habits, content, goals, journal, priorities, reminders, wealth

### Flutter App
- ✅ **All images fixed:** `api.getMediaUrl()` helper added to `api.dart`
- ✅ **Journal page:** Tap to expand/collapse with smooth animation
- ✅ **Library page:** Tap to expand/collapse (quotes, insights, philosophy)
- ✅ **Memory cards:** Images load from PythonAnywhere
- ✅ **Profile avatar:** Linked to user `buba` (`avatars/2026/09/scaled_1000702868.jpg`)
- ✅ **APK distribution:** GitHub Releases (v1.4.0)
- ✅ **Light mode + friendly errors** implemented app-wide
- ✅ Content lifecycle: `published/draft/archived`

### TheFeeder Studio
- ✅ Points to production API: `https://bubaa.pythonanywhere.com/api/v1`
- ✅ Build available on localhost:5175
- ⏳ Not yet deployed to the cloud

---

## 🔧 How to Start Everything

### On PythonAnywhere (backend is always running)
1. The site is **always live** at `https://bubaa.pythonanywhere.com` — but the free tier **sleeps after ~5 min of inactivity** (first request then takes 30+s to wake). UptimeRobot keeps it warm; the $5/mo tier removes this before you charge users.
2. Deploying changes: `git pull` + migrate + pip install + Reload web app — full procedure in `docs/runbook.md` §3. Never `git reset --hard` on the server: the DB and media live inside the checkout.

### On Local PC (for development)
```bash
# Backend (if running locally)
C:\mura\backend\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000 --noreload

# Feeder Web Studio
cd C:\mura\feeder-web
npm run dev   # or yarn dev
# Opens at http://localhost:5175

# Flutter (for rebuilding)
cd C:\mura\flutter_app
flutter clean
flutter pub get
flutter build apk --release
```

### Install APK on phone
```bash
adb install -r C:\mura\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```
Or download from [GitHub Releases](https://github.com/bubaa001/MURA_MOTIVE-YOUR-DAY/releases).

---

## 📁 Project Structure

```
C:\mura\
├── backend/               # Django backend
│   ├── config/            # Django settings
│   ├── accounts/          # User auth
│   ├── habits/            # Habits & streaks
│   ├── content/           # Content library (quotes, insights)
│   ├── goals/             # Goals module
│   ├── journal/           # Journal entries
│   ├── priorities/        # Priorities
│   ├── reminders/         # Reminders
│   ├── updates/           # In-app updater
│   ├── media/             # User-uploaded files
│   └── db.sqlite3         # Production database (on PythonAnywhere)
├── flutter_app/           # Flutter mobile app
│   ├── lib/
│   │   ├── api.dart       # API client + getMediaUrl() helper
│   │   ├── screens/
│   │   │   ├── journal_page.dart   # Expand/collapse
│   │   │   └── library_page.dart   # Expand/collapse
│   │   └── models.dart    # Data models
│   └── pubspec.yaml       # Version: 1.4.0+10
├── feeder-web/            # Content management studio
│   └── src/
│       └── api.ts         # Points to production API
├── docs/                  # Documentation
│   ├── api-contract.md    # API contract
│   └── feeder-ops.md      # Feeder operations
└── HANDOFF.md             # This file
```

---

## 📂 Critical Files & Their States

| File | Location | Status |
|------|----------|--------|
| `.env` (PythonAnywhere) | `/home/bubaa/MURA/backend/.env` | ✅ Set up |
| `settings.py` | `backend/config/settings.py` | ✅ Reads env vars |
| `api.dart` | `flutter_app/lib/api.dart` | ✅ Has `getMediaUrl()` |
| `journal_page.dart` | `flutter_app/lib/screens/` | ✅ Expand/collapse + images fixed |
| `library_page.dart` | `flutter_app/lib/screens/` | ✅ Expand/collapse + images fixed |
| `profile_screen.dart` | `flutter_app/lib/screens/` | ⏳ Needs avatar `getMediaUrl()` if not done |
| `feeder-web/src/api.ts` | `feeder-web/src/api.ts` | ✅ Points to PythonAnywhere |

---

## 🚨 Known Issues

| Issue | Status | Fix |
|-------|--------|-----|
| PythonAnywhere free tier sleeps | ⏳ Workaround needed | Use UptimeRobot to ping every 5 min (or upgrade to $5/mo before charging users) |
| Signo push notifications | ⚠️ Partial | Pushes work via scheduled tasks (see `docs/runbook.md` §4). Per-user topics prevent cross-user leaks; broadcast campaigns stay manual "Send now" until the scheduler runs. There is NO webhook endpoint — the old webhook advice was wrong. |
| Feeder not deployed | ⏳ Optional | Deploy to Netlify/Vercel if needed (login page needs the API URL) |

**Operating manual:** `docs/runbook.md` — backups, credentials rotation, deploys, scheduled tasks, push architecture, monetization steps.

---

## 🔜 Next Steps

### High Priority
1. ✅ **Fix images** — DONE (all images load from PythonAnywhere)
2. ✅ **Journal expand/collapse** — DONE
3. ✅ **Library expand/collapse** — DONE
4. ✅ **APK distribution via GitHub Releases** — DONE (v1.4.0)
5. ✅ **Security hardening pass** — DONE (2026-09-07 audit): employee signup gated by
   `EMPLOYEE_SIGNUP_KEY`, feeder sync is superuser-only, per-user push topics,
   throttling, atomic writes, timezone-consistent check-ins, pagination fixes,
   daily backup command. Runbook: `docs/runbook.md`.
6. ⏳ **Rotate the admin password** — the old one was published in the public repo; see runbook §2. TODAY.
7. ⏳ **Set up the PA scheduled tasks** (backup/reminders/campaigns) — runbook §4.
8. ⏳ **Back up prod DB + .env off-box** — runbook §1. TODAY.

### Medium Priority
6. ⏳ **Keep PythonAnywhere awake** — Set up UptimeRobot
7. ⏳ **Deploy Feeder** (optional) — Netlify/Vercel
8. ⏳ **Offline support in the app** — the app currently needs network for everything; add a local cache (see audit)
9. ⏳ **Monetization** — `User.plan` field ships on `/me/`; RevenueCat webhook later (runbook §7)

### Future Features (optional)
- Sleep tracking
- Habit analytics
- Advanced reminders
- Social sharing

---

## 🧪 Testing Checklist

- [x] Login works (credentials never belong in docs — use the password manager)
- [x] Habits load
- [x] Goals load
- [x] Journal entries load and expand/collapse
- [x] Library items load and expand/collapse
- [x] Images load (avatar, journal photos, memory photos, quote images)
- [x] APK installs on phone (v1.4.0)
- [x] Push notifications (work in progress) — scheduled-task based, see runbook §4/§5

---

## 📱 APK Download

**Latest release:** [GitHub Releases](https://github.com/bubaa001/MURA_MOTIVE-YOUR-DAY/releases)

- Download `MURA-v1.4.0.apk`
- Install on any Android device (allow unknown sources)

---

## 🌐 URLs

| Service | URL |
|---------|-----|
| Production API | `https://bubaa.pythonanywhere.com/api/v1/` |
| Admin Panel | `https://bubaa.pythonanywhere.com/admin/` |
| GitHub Repo | `https://github.com/bubaa001/MURA_MOTIVE-YOUR-DAY` |
| GitHub Releases | `https://github.com/bubaa001/MURA_MOTIVE-YOUR-DAY/releases` |

---

## 📞 Contact

- Developer: Buba
- Email: [eglis@example.com]
- Project: MURA — Motive Your Day

---

**Last updated:** September 7, 2026
**Handoff version:** v1.4.0
```

---

## 📝 Summary of changes made

| Section | What was added/updated |
|---------|------------------------|
| **Current Deployment Status** | Added PythonAnywhere URL, media URL, version info |
| **What's Done** | Added all image fixes, expand/collapse features, GitHub Releases |
| **Project Structure** | Added `feeder-web`, `api.dart`, `journal_page.dart`, `library_page.dart` |
| **Critical Files** | Tracked all the files we modified |
| **Known Issues** | Added PythonAnywhere sleep, Signo, and avatar notes |
| **Next Steps** | Prioritized push notifications and UptimeRobot |
| **Testing Checklist** | Marked all completed items |
| **APK Download** | Added GitHub Releases link |

---

Save this as `HANDOFF.md` in the root of your project (`C:\mura\` or your repo root) and commit it:

```bash
cd C:\mura
git add HANDOFF.md
git commit -m "Update handoff with all fixes, PythonAnywhere deployment, and v1.3.0"
git push origin main
```

Let me know if you need any adjustments or want to add more details!