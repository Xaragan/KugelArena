# Starts the game.
#   .\play.ps1                  you against the net
#   .\play.ps1 -Watch           the net plays both balls
#   .\play.ps1 -SecondScreen    open the window on the non-primary screen
param([switch]$Watch, [switch]$SecondScreen)
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64.exe"
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot. Put a Godot 4.7 build there or edit this script."; exit 1 }
# Godot loads the Steam extension only when it is listed in this file.
$list = Join-Path $PSScriptRoot ".godot\extension_list.cfg"
if (-not (Test-Path $list)) {
    New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot ".godot") | Out-Null
    Set-Content -Path $list -Value "res://addons/godotsteam/godotsteam.gdextension" -Encoding ascii
}
$extra = @()
if ($Watch) { $extra += "--watch" }
if ($SecondScreen) { $extra += "--second-screen" }
& $godot --path $PSScriptRoot -- @extra
