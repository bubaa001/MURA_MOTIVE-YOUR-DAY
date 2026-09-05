@echo off
title MURA Stopper
echo Stopping MURA services...

REM --- close the launcher windows by title ---
taskkill /F /FI "WINDOWTITLE eq MURA-Backend*" /T >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq MURA-ngrok*" /T >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq MURA-Studio*" /T >nul 2>&1

REM --- fallback: kill whatever is listening on MURA's ports ---
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":8000 .*LISTENING"') do taskkill /F /PID %%p >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":4040 .*LISTENING"') do taskkill /F /PID %%p >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /r /c:":5175 .*LISTENING"') do taskkill /F /PID %%p >nul 2>&1

echo Done.
ping -n 4 127.0.0.1 >nul