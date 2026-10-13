@echo off
rem ============================================================
rem  PIGMAN self-check gate  (P0-3)
rem  Double-click to run. No window, no editor needed.
rem  ALL GREEN = safe to commit.  Any FAIL = fix first.
rem  Same as: godot --headless --path . res://checks/selfcheck.tscn
rem ============================================================
set "GODOT=D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" (
	echo [ERROR] Godot not found at:
	echo         %GODOT%
	echo Edit this .cmd and fix the GODOT path.
	echo.
	pause
	exit /b 2
)

"%GODOT%" --headless --path "%~dp0." res://checks/selfcheck.tscn
echo.
echo ---- exit code %ERRORLEVEL%   (0 = all passed) ----
pause
