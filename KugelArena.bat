@echo off
rem Starts KugelArena. Double-click this file.
cd /d "%~dp0"
if not exist ".godot\extension_list.cfg" (
    echo First start: preparing the game, this takes a few seconds ...
    "tools\godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import >nul 2>&1
)
start "" "tools\godot\Godot_v4.7.2-stable_win64.exe" --path .
