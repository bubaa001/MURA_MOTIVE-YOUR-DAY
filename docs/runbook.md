# MURA Production Runbook

The live system: **https://bubaa.pythonanywhere.com** (PythonAnywhere free tier),
serving the MURA Android app and TheFeeder studio. This is the operating
manual for keeping it alive, secure, and backed up.

---

## 1. The golden rule: the database

The production SQLite database lives at `/home/bubaa/MURA/backend/db.sqlite3`
**inside the git working tree** — a `git reset --hard`, fresh clone, or disk-cap
failure would destroy it. It has no other copy unless you make one.

### Back up (do this NOW and then daily)

On the PythonAnywhere **Tasks** tab, create a scheduled task that runs daily:

```bash
cd /home/bubaa/MURA/backend && /home/bubaa/.virtualenvs/mura/bin/python manage.py db_backup
```

The command is read-only against the live DB (never destructive), writes
`backend/backups/mura-<timestamp>.json`, and prunes itself to the newest 30
files. Verify it ran:

```bash
ls -lh /home/bubaa/MURA/backend/backups/
```

**Then copy backups OFF the box** (PythonAnywhere disk is not a backup):
weekly, download the newest one or sync to Google Drive via `rclone`.

### Restore

```bash
cd /home/bubaa/MURA/backend
# ALWAYS snapshot the current DB before restoring anything:
cp db.sqlite3 db.sqlite3.pre-restore.$(date +%s)
.venv/bin/python manage.py loaddata backups/mura-<timestamp>.json
```

Loaddata is additive (it fails on conflicting PKs rather than overwriting),
so a full disaster restore means: fresh empty DB → migrate → loaddata.

### Also back up
- `backend/.env` — **the only copy of production secrets** (SECRET_KEY,
  SIGNO_NAMESPACE, EMPLOYEE_SIGNUP_KEY). Download it to your password manager
  / encrypted storage today. If it is lost, the API silently falls back to
  insecure defaults (or refuses to boot).
- `backend/media/` — user avatars, photos, feeder artwork. Zip and download
  occasionally: `tar czf media-$(date +%F).tgz backend/media/`

### Free up disk (the 512 MB cap)

`media/releases/` holds ~370 MB of legacy APKs that the app no longer uses
(updates come from GitHub Releases now). Safe to delete on the server:

```bash
rm -rf /home/bubaa/MURA/backend/media/releases/
```

---

## 2. Admin credentials

**The old password was published in a public repo — assume it is compromised.**

Rotate it now (then whenever anyone who knew it leaves):

```bash
cd /home/bubaa/MURA/backend && .venv/bin/python manage.py changepassword buba
```

Rules going forward:
- Never write real credentials in any repo file, doc, or chat output.
- Staff (feeder) accounts: create them yourself from Django admin, or share
  the `EMPLOYEE_SIGNUP_KEY` from `.env` with people you trust — registration
  without it is rejected.
- The `buba` account is the only superuser. Superuser-only actions: syncing
  feeder content live, publishing/restoring content, employee sync/unsync.

---

## 3. Deploying backend changes

```bash
ssh # or use the PA Bash console
cd /home/bubaa/MURA
git pull                       # NEVER run git reset --hard — the DB and media live here
cd backend
.venv/bin/python manage.py migrate    # additive by design; backup first if unsure
.venv/bin/pip install -r requirements.txt
```

Then on the PA **Web** tab: **Reload** the web app.

Before pulling: `python manage.py db_backup` — takes 5 seconds, saves everyone.

---

## 4. Scheduled tasks (PythonAnywhere Tasks tab)

The free tier allows a few scheduled tasks. Create these:

| Task | Command | Schedule |
|---|---|---|
| DB backup | `cd /home/bubaa/MURA/backend && .venv/bin/python manage.py db_backup` | Daily |
| Reminders | `cd /home/bubaa/MURA/backend && .venv/bin/python manage.py push_due_reminders` | Hourly |
| Campaigns | `cd /home/bubaa/MURA/backend && .venv/bin/python manage.py send_due_pushes` | Hourly |

Notes:
- Reminder pushes match a **due window** (past HH:MM within the last 2h), so
  hourly runs still deliver; a missed window self-heals on the next run for
  any reminder that day. Exact-minute precision is not possible on this host.
- Free-tier tasks are "daily at best" per the PA docs — if hourly is not
  available, reminders degrade gracefully: set them on the hour and accept
  batch delivery. For real-time pushes later, upgrade to the $5/mo tier.

---

## 5. Push notifications (Signo) — architecture

- **Global namespace** (`SIGNO_NAMESPACE`): reaches every subscribed device.
  Used ONLY by the studio's broadcast campaigns.
- **Per-user topics** (`{SIGNO_NAMESPACE}:{user_id}`): personal events
  (streak milestones, goal wins, reminders) go here and nowhere else — this
  is what prevents one user's habit names from landing on another user's
  phone. A device only receives personal pushes once it subscribes to its
  user's topic in the Signo app.

---

## 6. Publishing an app update

```powershell
# bump version in flutter_app/pubspec.yaml, build, then:
cd backend
$env:GITHUB_TOKEN = "<token>"
.venv\Scripts\python manage.py publish_release `
    --apk ..\flutter_app\build\app\outputs\flutter-apk\app-release.apk `
    --version-name 1.3.1 --version-code 10 --notes "what changed" `
    --github bubaa001/MURA_MOTIVE-YOUR-DAY
```

APKs are hosted on GitHub Releases — **never commit APKs to git** (the
`.gitignore` now blocks `*.apk`).

---

## 7. Monetization groundwork (already in the code)

`User.plan` (`free` | `premium`) ships on `/api/v1/me/`. The intended flow:

1. Add RevenueCat (or Play Billing) to the Flutter app.
2. Point its webhook at a small endpoint that sets `User.plan` on
   purchase/cancellation.
3. Gate premium features client-side on `plan` from `/me/` — good candidates:
   wealth tracking, unlimited history depth, custom reminder counts.
4. Before charging money: move to the $5/mo PythonAnywhere tier (free tier
   sleeps = paid users staring at error screens) and write a privacy policy.

---

## 8. Emergency: "the site is down"

1. PA Web tab → check the error log link at the bottom of the page.
2. Most common: disk quota (`df -h ~`) — delete `media/releases/` and old logs.
3. After a bad deploy: `git stash` (NOT reset), Reload, check again.
4. Worst case (DB corruption): restore from `backups/` per section 1.
