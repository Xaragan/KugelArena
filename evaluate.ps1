# Measures the game's net against the scripted baseline on games training never saw.
#   .\evaluate.ps1                      2000 games against the baseline bot
#   .\evaluate.ps1 -Opponent panel      against four scripted characters
#   .\evaluate.ps1 -Net bot             the baseline bot against itself, for comparison
param([int]$Games = 2000, [string]$Opponent = "std", [string]$Net = "res://net/rival_net.json")
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot."; exit 1 }
& $godot --headless --path $PSScriptRoot --script res://training/evaluate.gd -- "--games=$Games" "--opponent=$Opponent" "--net=$Net"
