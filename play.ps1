# Starts the game.
#   .\play.ps1                  you against the net
#   .\play.ps1 -Watch           the net plays both balls
#   .\play.ps1 -SecondScreen    open the window on the non-primary screen
param([switch]$Watch, [switch]$SecondScreen)
$godot = Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64.exe"
if (-not (Test-Path $godot)) { Write-Error "Godot not found at $godot. Put a Godot 4.7 build there or edit this script."; exit 1 }
# The Steam extension is only loaded once Godot has scanned the project.
if (-not (Test-Path (Join-Path $PSScriptRoot ".godot\extension_list.cfg"))) {
    & (Join-Path $PSScriptRoot "tools\godot\Godot_v4.7.2-stable_win64_console.exe") --headless --path $PSScriptRoot --import | Out-Null
}
$extra = @()
if ($Watch) { $extra += "--watch" }
if ($SecondScreen) { $extra += "--second-screen" }
& $godot --path $PSScriptRoot -- @extra
