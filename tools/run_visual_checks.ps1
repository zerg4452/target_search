# 시각 검사 V-01~V-03(§14.3)을 창 모드로 실행한다(GPU 필요). 결과: test_reports/visual/
#   pwsh tools/run_visual_checks.ps1                 # 전체
#   pwsh tools/run_visual_checks.ps1 -Only V-01      # 하나만
#   pwsh tools/run_visual_checks.ps1 -Filter VA0     # 변이 ID 일부로 거르기(V-01)
param(
    [string]$Godot = $env:GODOT,
    [string]$Only = "",
    [string]$Filter = ""
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$raw = Join-Path $repo 'test_reports/raw'
New-Item -ItemType Directory -Force $raw | Out-Null
if (-not $Godot) {
    $Godot = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path $Godot)) { throw "Godot executable not found: $Godot (pass -Godot or set GODOT)" }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$log = Join-Path $raw "visual_checks_$stamp.log"
& $Godot --headless --path $repo --import 2>&1 | Out-Null
$a = @('--path', $repo, '--script', 'res://tests/visual/run_visual_checks.gd', '--')
if ($Only) { $a += "--only=$Only" }
if ($Filter) { $a += "--filter=$Filter" }
& $Godot @a 2>&1 | Tee-Object -FilePath $log
$code = $LASTEXITCODE
Write-Host "log: $log (exit $code)"
exit $code
