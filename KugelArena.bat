@echo off
rem Starts KugelArena. Double-click this file.
cd /d "%~dp0"
if not exist ".godot" mkdir ".godot"
if not exist ".godot\extension_list.cfg" echo res://addons/godotsteam/godotsteam.gdextension> ".godot\extension_list.cfg"
start "" "tools\godot\Godot_v4.7.2-stable_win64.exe" --path .
