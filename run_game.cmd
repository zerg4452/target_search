@echo off
setlocal
cd /d "%~dp0"
rem Godot 4.7.2 Standard. Set GODOT_EXE to use a specific executable.
if not defined GODOT_EXE set "GODOT_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 Standard not found. Set GODOT_EXE.
  pause
  exit /b 1
)
start /wait "" "%GODOT_EXE%" --headless --path "%~dp0." --import
rem Extra args example: run_game.cmd --seed=7 --skip-intro --debug-overlay
start "" "%GODOT_EXE%" --path "%~dp0." -- %*
