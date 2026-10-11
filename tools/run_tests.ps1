# 자동 검사(헤드리스, T-01~T-15)를 실행하고 콘솔 출력을 test_reports/raw/에 남긴다.
#   pwsh tools/run_tests.ps1                    # 전체
#   pwsh tools/run_tests.ps1 -Filter t03        # 이름 일부로 거르기
#   pwsh tools/run_tests.ps1 -Godot <path>      # Godot 4.7.2 console 실행 파일 지정
param(
    [string]$Godot = $env:GODOT,
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
$log = Join-Path $raw "tests_$stamp.log"

& $Godot --headless --path $repo --import 2>&1 | Out-Null
$testArgs = @('--headless', '--path', $repo, '--script', 'res://tests/run_tests.gd')
if ($Filter) { $testArgs += @('--', "--filter=$Filter") }
& $Godot @testArgs 2>&1 | Tee-Object -FilePath $log
$code = $LASTEXITCODE
Write-Host "log: $log (exit $code)"
exit $code
