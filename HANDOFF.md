# MURA — Project Handoff (read this first)

Personal discipline app for Buba. Backend: Django REST API. Mobile: was React Native/Expo — user has decided to switch to Flutter (RN toolchain caused repeated failures on their Windows PC + Samsung phone).

## Run locations
- EVERYTHING lives at C:\mura\ (moved off deep path — Windows 260-char limit broke RN builds)
- Backend: C:\mura\backend\ — venv at .venv, run: .venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000 --noreload
- Login: username buba / password buba (admin at /admin/)
- API base: http://localhost:8000/api/v1/ (phone via USB: adb reverse tcp:8000 tcp:8000)
- Old stale copy at C:\Users\eglis\Documents\harness001\product\ — ignore/delete later
- Phone: Samsung SM-G998U, USB debugging authorized (id R5CR31ELEPB). PC LAN IP: 192.168.0.107


## FINAL STATE (2026-08-30 — handover to Android Studio + Google Pixel)

Everything below is committed at **e013003** (working tree clean). Backend suite: 116 tests green.

- **App**: `flutter_app` IS the product (the RN `mobile/` is reference only). Current build **v1.1.0+2** with in-app updater; latest shareable APK on the Desktop (`MURA.apk`) and at `flutter_app/build/app/outputs/flutter-apk/app-release.apk`.
- **Stack today**: Django + SQLite backend, TheFeeder studio (`feeder-web`, http://localhost:5175, sign in **buba / buba**), phone app reaches it via the ngrok static domain `https://crusader-easing-overlying.ngrok-free.dev` (baked into the app).
- **Start everything**: double-click **`MURA-Start.bat`** on the Desktop (backend + ngrok + studio; `MURA-Stop.bat` to stop). Backend must run on THIS PC for the phone/Pixel app to work.
- **TheFeeder** is the publishing studio (write → review → sync → Live Content manager). Book/AI extraction erased. See `docs/feeder-ops.md`.
- **Light mode + friendly errors** implemented app-wide; content has `published/draft/archived` lifecycle; motion quotes seeded.
- **In-app updater**: `GET /api/v1/update/` manifest; publish a build with `python manage.py publish_release --apk <path> --version-name X.Y.Z --version-code N --notes "..."` (bump `flutter_app/pubspec.yaml` version first). No releases currently published (test one removed).
- **Android Studio**: open `C:\mura\flutter_app`; Android SDK at `C:\Users\eglis\AppData\Local\Android\Sdk` (configured in Flutter). Install on the Pixel over USB via Run or `flutter run`, or sideload the Desktop `MURA.apk` (allow unknown apps once).
- **Emulator** available: `emulator-5554` (sdk_gphone64). Phone (Samsung R5CR31ELEPB) adb-authorized; Pixel to come.

## Older notes below are historical
## What is DONE and works
- Django 6.1 + DRF backend: accounts (JWT), habits (streak engine w/ grace days in habits/services.py), content (daily rotation feed), goals, journal+memories, priorities, reminders
- 81/81 tests pass (python manage.py test from backend dir)
- Seeded quotes/prayers/philosophies; bootstrap_dev command makes demo data + user
- Docker deploy files + docs/deployment.md
- API contract: C:\mura\docs\api-contract.md — THE source of truth for endpoints/shapes
- Design system: C:\mura\stitch_zenith_discipline_app_ui\obsidian_amber\DESIGN.md (Obsidian & Amber: near-black surfaces, amber primary, Sora display + Hanken Grotesk body, glass blur bottom nav)

## Next steps (Flutter rebuild)
1. Install Flutter SDK (Dart 3.12 already present). Verify with flutter doctor
2. Create C:\mura\flutter_app (flutter create mura --org com.bubaa)
3. Implement screens per DESIGN.md against api-contract.md:
   login -> tabs: Today (checklist+quote card), Habits (heatmap/streaks), Plan (priorities+goals), Journal (entries+memories w/ photo), Library (quotes/prayer/philosophy), Settings
   API client: base URL http://localhost:8000/api/v1 in dev (adb reverse tcp:8000 tcp:8000); JWT auth header;
   today endpoint returns {date, items:[...]}; habit toggle returns flat {completed, current_streak, best_streak, ...}
4. Release to phone: flutter build apk --release then adb install -r build\app\outputs\flutter-apk\app-release.apk
5. For LAN use without USB: bake http://192.168.0.107:8000/api/v1 and allow port 8000 in Windows Firewall

## Known gotchas
- Emulators available: Pixel_10_Pro_XL, moviebox_phone (use -no-window for headless testing)
- RN app kept at C:\mura\mobile\ for UX reference only; babel.config.js fix + index.tsx redirect applied there late
- Samsung may pull notification shade over app during adb installs — collapse via: adb shell cmd statusbar collapse