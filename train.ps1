# Trains the rival's net. Continues the run if it already exists.
#   .\train.ps1                 30 minutes on the run "main"
#   .\train.ps1 -Minutes 120    longer
#   .\train.ps1 -Fresh          throw the run away and start from a random net
#   .\train.ps1 -Stop           ask a running training to stop after its current generation
param([double]$Minutes = 30, [string]$Run = "main", [switch]$Fresh, [switch]$Stop, [int]$Workers = 0)
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot. Put a Godot 4.7 build there or edit this script."; exit 1 }
$runDir = Join-Path $PSScriptRoot "training\runs\$Run"
if ($Stop) {
    New-Item -ItemType Directory -Force $runDir | Out-Null
    New-Item -ItemType File -Force (Join-Path $runDir "STOP") | Out-Null
    Write-Host "Stop requested for run '$Run'."
    exit 0
}
$extra = @("--minutes=$Minutes", "--run=$Run")
if ($Fresh) { $extra += "--fresh" }
if ($Workers -gt 0) { $extra += "--workers=$Workers" }
& $godot --headless --path $PSScriptRoot --script res://training/train.gd -- @extra
