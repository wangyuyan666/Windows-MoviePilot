@echo off
rem MoviePilot Windows portable launcher.
rem Comments are ASCII-only on purpose: this file is parsed under the console
rem code page, and non-ASCII bytes there are a known source of breakage.
rem
rem Started by MoviePilot.vbs with a hidden window. Starts nginx, runs the
rem backend in the foreground, and shuts nginx down once the backend exits
rem (tray "exit" or a crash), so no orphan nginx is left behind.

setlocal

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

set "NGINX_DIR=%APP_DIR%\Nginx"
set "PYTHON_EXE=%APP_DIR%\Python\python.exe"
set "SERVER_DIR=%APP_DIR%\MoviePilot"

rem User data lives outside MoviePilot\ so upgrades can replace it wholesale.
set "CONFIG_DIR=%APP_DIR%\config"
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%NGINX_DIR%\logs" mkdir "%NGINX_DIR%\logs"
if not exist "%NGINX_DIR%\temp" mkdir "%NGINX_DIR%\temp"

if not exist "%PYTHON_EXE%" (
    echo [ERROR] Python runtime not found: %PYTHON_EXE%
    exit /b 1
)
if not exist "%SERVER_DIR%\app\main.py" (
    echo [ERROR] MoviePilot source not found: %SERVER_DIR%\app\main.py
    exit /b 1
)

rem Clear a stale instance left by an unclean shutdown. Scoped to our own
rem prefix, so a user's separately installed nginx is never touched.
"%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf -s quit >nul 2>&1

"%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf
if errorlevel 1 (
    echo [ERROR] nginx failed to start, see %NGINX_DIR%\logs\error.log
    exit /b 1
)

cd /d "%SERVER_DIR%"
"%PYTHON_EXE%" app\main.py
set "BACKEND_EXIT=%ERRORLEVEL%"

"%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf -s quit >nul 2>&1

endlocal & exit /b %BACKEND_EXIT%
