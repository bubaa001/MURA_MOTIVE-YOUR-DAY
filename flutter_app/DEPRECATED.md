# ⚠️ DEPRECATED — do not run this app

This Flutter prototype is an abandoned earlier iteration of MURA.

- It hardcodes a DEAD ngrok tunnel URL (`crusader-easing-overlying.ngrok-free.dev`) in `lib/api.dart` — every request fails.
- It is NOT maintained; the product lives in `../mobile` (Expo/React Native) + `../backend` (Django).
- Its `build/` artifacts (~1 GB of stale APKs) are safe to delete.

Use `cd ../mobile && npx expo start` instead.
