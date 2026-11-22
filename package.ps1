# Packs everything a friend needs to play into dist\KugelArena.zip (about 110 MB):
# the game, the trained nets, the Steam extension and the Godot runtime.
# Your friend unpacks it and double-clicks KugelArena.bat. Steam must be running.
$root = $PSScriptRoot
$stage = Join-Path $root "dist\KugelArena"
if (Test-Path (Join-Path $root "dist")) { Remove-Item -Recurse -Force (Join-Path $root "dist") }
New-Item -ItemType Directory -Force $stage | Out-Null
foreach ($item in @("project.godot", "KugelArena.bat", "README.md", "LICENSE", "game", "sim", "net", "addons")) {
    Copy-Item -Recurse (Join-Path $root $item) $stage
}
New-Item -ItemType Directory -Force (Join-Path $stage "tools\godot") | Out-Null
Copy-Item (Join-Path $root "tools\godot\*.exe") (Join-Path $stage "tools\godot")
New-Item -ItemType File -Force (Join-Path $stage "tools\.gdignore") | Out-Null
# Tells Godot to load the Steam extension without the editor having scanned the project.
New-Item -ItemType Directory -Force (Join-Path $stage ".godot") | Out-Null
Set-Content -Path (Join-Path $stage ".godot\extension_list.cfg") -Value "res://addons/godotsteam/godotsteam.gdextension" -Encoding ascii
# Of the training runs only what the menu and the replays show.
Get-ChildItem (Join-Path $root "training\runs") -Directory | ForEach-Object {
    $target = Join-Path $stage ("training\runs\" + $_.Name)
    New-Item -ItemType Directory -Force $target | Out-Null
    foreach ($name in @("nets", "net_best.json", "highlights.jsonl", "progress.md")) {
        $source = Join-Path $_.FullName $name
        if (Test-Path $source) { Copy-Item -Recurse $source $target }
    }
}
$zip = Join-Path $root "dist\KugelArena.zip"
Compress-Archive -Path $stage -DestinationPath $zip
Write-Host ("Written: " + $zip + "  (" + [math]::Round((Get-Item $zip).Length / 1MB) + " MB)")
