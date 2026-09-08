# MURA 1.4.0 — Automations + Native Push (FCM) + Animations + Profile Redesign + Widget Polish

## Part 1 — Native app notifications via Firebase Cloud Messaging (replaces Signo for users)

The problem: Signo pushes only arrive if the user installed the Signo app. FCM is Google's free push channel — every Android phone receives FCM natively, no third-party app.

**Backend:**
- New `DeviceToken` model (accounts app): `user`, `token` (unique), `platform`, `is_active`, `created_at`. Endpoint `POST /api/v1/me/devices/` to register a device, auto-cleanup on logout.
- New sender module `backend/push/fcm.py`: sends via FCM HTTP v1 API using a service-account JWT (adds `PyJWT` crypto support → `cryptography` in requirements.txt). Best-effort semantics identical to Signo's (try/except, never fail the parent request), access-token cached, dead tokens (404 UNREGISTERED) marked inactive.
- New unified helper `notify_user(user, title, body, payload)`: **FCM first** to all active device tokens; **Signo fallback only if no device is registered** (so you, with Signo installed, lose nothing during transition).
- Route through it: automations (new), reminders (`push_due_reminders`), streak milestones, goal completions, campaigns — all switch from `send_user_event` to `notify_user`.
- Env: `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY` in `.env` (server-side secret, never committed; `.env.example` documents them).
- In-app notification feed (NotificationLog → /notifications/) keeps working unchanged — it's the guaranteed channel; pushes are the bonus layer.

**Flutter app:**
- Add `firebase_messaging`, `firebase_core`, `flutter_local_notifications` (to display pushes while app is closed/backgrounded), initialized with manual `FirebaseOptions` (no google-services.json/gradle plugin needed — the 4 client values are safe to commit; the private key never leaves the server).
- Flow: on login → request Android 13+ notification permission → get FCM token → register to `/me/devices/`; re-register on token refresh; unregister on logout.
- Notification tap → opens MURA (deep-linking to specific tabs can come later).

**⚠️ What I need from YOU (the only blocking external step):**
1. Go to console.firebase.google.com (free, your Google account) → create a project (e.g. "MURA").
2. In it: add an Android app with package name **`com.bubaa.mura`**.
3. From its config, give me 4 values (safe to commit): **API key, Project ID, Sender ID, App ID** — or just paste/drop the downloaded `google-services.json` file and I'll extract them.
4. Project Settings → Service accounts → **Generate new private key** → that JSON file's contents go into `backend/.env` locally AND later into the PythonAnywhere `.env` (never committed to the repo).
5. At deploy time on PA (I'll give exact commands): `pip install -r requirements.txt`, add the FCM_* vars, reload.

Until you hand me step 3+4, I'll build everything with a graceful fallback: the app builds and works, push activates the moment the Firebase values arrive.

## Part 2 — Backend: new `automations` app (full version: reactive + time-based)

- `AutomationRule` model: user, name, trigger_type + config JSON, action_type + config JSON, `is_active`, `last_fired_date` dedup, timestamps.
- Triggers: `habit_done` (specific/any), `all_habits_done`, `streak_reached` (custom N), `goal_achieved` (reactive — fire instantly after the atomic block in the existing toggle/complete views), plus `daily_nudge` (at HH:MM, optionally "only if habits incomplete" — evaluated by a new `run_automations` scheduled command mirroring `push_due_reminders`: catch-up window, same-day dedup, `--dry-run`).
- Actions v1: templated push + in-app notification (new "automation" kind in NotificationLog).
- API: user-scoped viewset at `/api/v1/automations/`, explicit-fields serializers with config validation, PATCH toggling.
- Tests in house style; full suite must stay green (currently 120).

## Part 3 — Flutter: Profile redesign (replaces the "awful" settings page)

- New `profile_page.dart` (route stays `/settings`): hero header — big avatar in animated amber ring, name, `@username`, plan badge (first time `User.plan` is shown), member since.
- Stats row with count-up animation: best streak, active habits, journal entries, goals achieved (data from existing endpoints); achievements strip derived client-side.
- Actions card: edit name, appearance, **Automations tile → new AutomationsPage**, log out. The fake notifications toggle is removed.
- Fixes: real version via `package_info_plus` (kills the wrong `v1.0.0`), back button, theme-aware colors (no hard-coded dark values breaking light mode), unified avatar widget.
- Animations: staggered card entrance, avatar crossfade, stats count-up, shimmer loading.

## Part 4 — Flutter: app-wide animation pass

- Tab shell: `KeyedSubtree` remount → `IndexedStack` (state preserved, no hard cut, no refetch-on-switch).
- New shared `lib/widgets/`: `MuraCard`, `Pressable` (press-scale+glow), `FadeSlideIn` (stagger), `StatChip`.
- Page motion: habits heatmap diagonal pop-in stagger + 7-day dot springs + counters; today/plan progress bars tween (kills `AlwaysStoppedAnimation`); streak chip pops in; wealth metrics count up; journal/library list stagger.
- All motion matches the existing family: easeOutCubic, 200–350ms, amber glow. No new exotic curves.

## Part 5 — Android widgets: polish within RemoteViews limits

Honest ceiling: launchers don't allow free-flowing motion. What's possible and classy:
- Quote + Insight widgets: `ViewFlipper` fade-cycling content.
- Today's Habits widget: determinate `ProgressBar` under "n/N done" — fills as the day completes.
- Streak widget: progress bar toward next milestone (3/7/14/30/100).

## Part 6 — Ship

- Version → `1.4.0+10`; backend tests green; `flutter analyze` + tests; `flutter build apk --release`.
- Docs: runbook §4 gains the `run_automations` task + FCM setup section; api-contract gains automations + devices endpoints.
- Commit + push; you get the PA deploy checklist (pull, migrate, pip install, env vars, reload, 2 scheduled tasks).

**Out of scope:** no offline cache, no state-management rewrite, no new server infrastructure beyond FCM HTTP calls.
