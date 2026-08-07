@echo off
rem MoviePilot Windows portable launcher.
rem Comments are ASCII-only on purpose: this file is parsed under the console
rem code page, and non-ASCII bytes there are a known source of breakage.
rem
rem Started by MoviePilot.vbs with a hidden window. Starts nginx, runs the
rem backend in the foreground, and shuts nginx down once the backend exits
rem (tray "exit" or a crash), so no orphan nginx is left behind.
rem
rem No parenthesised blocks anywhere below, only `goto`. cmd expands %VAR%
rem while parsing a whole `if (...)` block, so an install path containing
rem parentheses -- "C:\Program Files (x86)\..." -- closes the block early and
rem kills the script before the first command ever runs. Labels sidestep that
rem entirely, and unlike delayed expansion they also leave `!` in paths alone.

setlocal EnableExtensions

set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

set "NGINX_DIR=%APP_DIR%\Nginx"
set "PYTHON_EXE=%APP_DIR%\Python\python.exe"
set "SERVER_DIR=%APP_DIR%\MoviePilot"

rem User data lives outside MoviePilot\ so upgrades can replace it wholesale.
set "CONFIG_DIR=%APP_DIR%\config"
set "LOG_FILE=%CONFIG_DIR%\launcher.log"
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"

if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul

rem Everything from here on is logged. The window is hidden in normal use, so
rem a failure that happens before the backend starts would otherwise leave no
rem trace at all -- which is exactly how the parenthesis bug above stayed
rem invisible. Re-run self once with output redirected, the env var marks the
rem inner run so it does not recurse.
if defined MP_LAUNCHER_LOGGING goto :main
set "MP_LAUNCHER_LOGGING=1"
rem Keep the log from growing without bound now that every run appends to it.
if exist "%LOG_FILE%" for %%A in ("%LOG_FILE%") do if %%~zA GEQ 1048576 move /y "%LOG_FILE%" "%LOG_FILE%.old" >nul 2>&1
call "%~f0" >> "%LOG_FILE%" 2>&1
exit /b %ERRORLEVEL%

:main
echo.
echo ===== %DATE% %TIME% launcher start =====
echo [INFO] app dir: "%APP_DIR%"

if not exist "%NGINX_DIR%\logs" mkdir "%NGINX_DIR%\logs" 2>nul
if not exist "%NGINX_DIR%\temp" mkdir "%NGINX_DIR%\temp" 2>nul

if not exist "%PYTHON_EXE%" goto :err_python
if not exist "%SERVER_DIR%\app\main.py" goto :err_server

rem Clear a stale instance left by an unclean shutdown. Scoped to our own
rem prefix, so a user's separately installed nginx is never touched.
"%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf -s quit >nul 2>&1
if exist "%NGINX_DIR%\logs\nginx.pid" del /q "%NGINX_DIR%\logs\nginx.pid" >nul 2>&1

rem nginx for Windows holds the console instead of daemonising, so it has to
rem be detached with `start /b` or the backend below would never run.
echo [INFO] starting nginx
start "" /b "%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf

rem The pid file is the only reliable readiness signal here: `start` returns
rem immediately and reports its own exit code, not nginx's.
set /a NGINX_WAIT=0
:wait_nginx
if exist "%NGINX_DIR%\logs\nginx.pid" goto :nginx_ready
if %NGINX_WAIT% GEQ 20 goto :err_nginx
set /a NGINX_WAIT+=1
rem ping instead of timeout: timeout aborts when stdin is redirected
ping -n 2 127.0.0.1 >nul 2>&1
goto :wait_nginx

:nginx_ready
echo [INFO] nginx ready, starting backend
cd /d "%SERVER_DIR%"
rem Startup failures (import errors and the like) happen before MoviePilot's
rem own logging is initialised, so they only survive in this log.
"%PYTHON_EXE%" app\main.py
set "BACKEND_EXIT=%ERRORLEVEL%"
echo [INFO] backend exited with %BACKEND_EXIT%, stopping nginx

"%NGINX_DIR%\nginx.exe" -p "%NGINX_DIR%" -c conf\nginx.conf -s quit >nul 2>&1

endlocal & exit /b %BACKEND_EXIT%

:err_python
echo [ERROR] Python runtime not found: "%PYTHON_EXE%"
exit /b 1

:err_server
echo [ERROR] MoviePilot source not found: "%SERVER_DIR%\app\main.py"
exit /b 1

:err_nginx
echo [ERROR] nginx did not start, see "%NGINX_DIR%\logs\error.log"
exit /b 1
