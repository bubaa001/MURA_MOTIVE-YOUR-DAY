# MURA — Engineering audit & fix log

Full-stack audit (backend + Expo app) with end-to-end verification.

## Verification results (all green)

| Check | Result |
|---|---|
| Django test suite | **81/81 pass** |
| `tsc --noEmit` (mobile) | **0 errors** |
| Live API probe (`me/`, `content/daily/`, `habits/today/`, `heatmap`, `priorities/`, `goals/`, `journal/entries/`, `memories/`, `reminders/`) | **all 200** |
| Login + habit toggle round-trip | **OK** |

## Root causes found (why it "didn't work at all")

1. **Stale LAN IP in `mobile/.env`** — pointed at `192.168.0.107`; the dev machine is now `192.168.0.103`. Every request from a physical device died at the network layer. → Fixed to the live IP.
2. **Dev login credentials were broken** — `buba`'s stored password no longer matched the documented one, so sign-in returned 401 even with correct networking. → Password reset to `buba` (see README quickstart).
3. **Abandoned Flutter prototype (`flutter_app/`) hardcodes a dead ngrok tunnel** — anyone running it gets 100% failure. → Marked `flutter_app/DEPRECATED.md`; use `mobile/` instead. Its ~1 GB `build/` dir is safe to delete.
4. **JWT HMAC key < 32 bytes** (PyJWT warning on every token op). → Proper-length dev `SECRET_KEY` added to `backend/.env`. Note: this invalidates previously issued tokens — just sign in again.
5. **Dev DB polluted with QA junk users** (`qa_*`, `probe*`, `tunneltest`). → Deleted.

## Things audited and confirmed CORRECT (no change needed)

- Route map: every path in `mobile/src/lib/endpoints.ts` matches the backend mounts under `/api/v1/` (incl. `/auth/token|refresh|register/`, `/me/`, `/habits/today|toggle|history|heatmap_data/`, `/priorities/reorder/`, `/goals/{id}/complete/`, `/journal/entries/`, `/memories/`, `/content/daily|items/`).
- expo-router structure: root `_layout` auth-gate via `Stack.Protected`, `(tabs)` group, `index` redirect, `+not-found` — sound.
- Transport: auto token refresh once on 401, auth endpoints exempted, paginated `listAll` walker, optimistic updates with rollback in all stores.
- Streak/grace-day engine (`habits/services.py`): rolling-window budget, no consecutive forgiveness, unchecked-today-is-pending — matches docs; covered by tests.
- Reminder weekday mapping contract (Mon=0 → expo weekday), notification scheduling/rescheduling.

## Run it

```bash
# terminal 1
cd backend && .\.venv\Scripts\python manage.py runserver 0.0.0.0:8000

# terminal 2
cd mobile && npx expo start   # press a for Android
```

Phone and PC must share Wi-Fi; if the PC IP changes again, update `EXPO_PUBLIC_API_URL` in `mobile/.env` (currently `http://192.168.0.103:8000/api/v1`) and restart Metro — `EXPO_PUBLIC_*` values are baked at bundle time.
