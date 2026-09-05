@echo off
setlocal
title MURA Launcher
echo ============================================
echo   MURA - starting backend, tunnel and studio
echo ============================================
echo.

REM --- read the ngrok authtoken from backend/.env ---
set "NGROK_AUTHTOKEN="
for /f "usebackq tokens=1,* delims==" %%a in (`findstr /b "NGROK_AUTHTOKEN" "C:\mura\backend\.env"`) do set "NGROK_AUTHTOKEN=%%b"
if "%NGROK_AUTHTOKEN%"=="" echo [warn] no NGROK_AUTHTOKEN in backend/.env - tunnel may fail

REM --- 1) Django backend (SQLite, port 8000) ---
start "MURA" cmd /k "title MURA-Backend && cd /d C:\mura\backend && .venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000 --noreload"

REM --- 2) ngrok public tunnel (same static URL the phone app uses) ---
start "MURA" cmd /k "title MURA-ngrok && set "NGROK_AUTHTOKEN=%NGROK_AUTHTOKEN%" && ngrok http 8000 --url=https://crusader-easing-overlying.ngrok-free.dev"

REM --- 3) TheFeeder studio (React dashboard, port 5175) ---
start "MURA" cmd /k "title MURA-Studio && cd /d C:\mura\feeder-web && npm run dev"

echo Waiting for services to come up...
ping -n 9 127.0.0.1 >nul

REM --- open the studio in the default browser ---
start "" http://localhost:5175

echo.
echo All started. Three windows should now be open:
echo   MURA-Backend   - API on http://localhost:8000
echo   MURA-ngrok     - public tunnel https://crusader-easing-overlying.ngrok-free.dev
echo   MURA-Studio    - TheFeeder on http://localhost:5175  (sign in: buba / buba)
echo.
echo Phone app uses: https://crusader-easing-overlying.ngrok-free.dev
echo To stop everything later, double-click MURA-Stop.bat on the desktop.
echo.
endlocal