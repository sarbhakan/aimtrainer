param([string]$Godot = "godot")

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Invoke-GodotChecked([string[]]$GodotArguments) {
    $Output = & $Godot @GodotArguments 2>&1
    $ExitCode = $LASTEXITCODE
    $Output | ForEach-Object { Write-Output $_ }
    if ($ExitCode -ne 0 -or ($Output -join "`n") -match "(?m)^(SCRIPT ERROR:|ERROR:)") {
        throw "Godot en échec : $($GodotArguments -join ' ')"
    }
}

Push-Location $ProjectRoot
try {
    $Version = & $Godot --version
    if ($LASTEXITCODE -ne 0 -or $Version -notlike "4.7.2.stable.*") {
        throw "Godot 4.7.2 stable requis ; version détectée : $Version"
    }
    New-Item -ItemType Directory -Force -Path dist | Out-Null
    Invoke-GodotChecked @("--headless", "--path", ".", "--editor", "--import")
    Invoke-GodotChecked @("--headless", "--path", ".", "--script", "res://tests/run_tests.gd")
    foreach ($TestName in @("v2_foundation_tests", "v2_motion_tests", "v2_catalog_tests", "v2_runtime_tests", "v2_event_tests", "v2_calibration_tests", "v2_calibration_task_tests", "v2_store_tests", "v2_ui_tests", "v2_app_flow_tests", "v2_calibration_runner_tests", "v2_progress_tests", "v2_cal_flow_tests")) {
        Invoke-GodotChecked @("--headless", "--path", ".", "--script", "res://tests/$TestName.gd")
    }
    Invoke-GodotChecked @("--headless", "--path", ".", "--export-release", "Windows Desktop", "dist/AimLocal.exe")
    Write-Output "Exécutable : $ProjectRoot/dist/AimLocal.exe"
}
finally {
    Pop-Location
}
