@echo off
title BikeReclaim Dev
set SDK=%LOCALAPPDATA%\Android\Sdk
set EMU_ID=Medium_Phone_API_36.1

echo [1/3] Starting server window...
start "BikeReclaim Server" cmd /k "cd /d "%~dp0server" && py -m uvicorn main:app --host 0.0.0.0"

echo [2/3] Checking emulator...
"%SDK%\platform-tools\adb.exe" devices 2>nul | findstr "emulator-" >nul
if errorlevel 1 (
    echo     Launching emulator %EMU_ID% ...
    start "Emulator" "%SDK%\emulator\emulator.exe" -avd %EMU_ID% -no-snapshot-load
    echo     Waiting for device...
    "%SDK%\platform-tools\adb.exe" wait-for-device
    echo     Waiting 60s for Android boot...
    timeout /t 60 /nobreak >nul
) else (
    echo     Emulator already running.
)

echo [3/4] Reverting WebView auto-update (kakao map fix)...
"%SDK%\platform-tools\adb.exe" uninstall com.google.android.webview >nul 2>&1

echo [4/4] Building and running app... Keys: R = hot restart, q = quit
cd /d "%~dp0app"
call flutter run --no-enable-impeller

echo.
echo App session ended.
pause
