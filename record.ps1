# Plays headless games and records each one as data (recordings\*.jsonl).
#   .\record.ps1                       50 games, the game's net against itself
#   .\record.ps1 -B bot -Games 200     the net against the scripted baseline
#   -A / -B take a net file (res://... or a full path), "bot" or "varied"
param([int]$Games = 50, [string]$A = "res://net/rival_net.json", [string]$B = "res://net/rival_net.json")
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot."; exit 1 }
& $godot --headless --path $PSScriptRoot --script res://training/record.gd -- "--games=$Games" "--a=$A" "--b=$B"
