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
    Invoke-GodotChecked @("--headless", "--path", ".", "--export-release", "Windows Desktop", "dist/AimLocal.exe")
    Write-Output "Exécutable : $ProjectRoot/dist/AimLocal.exe"
}
finally {
    Pop-Location
}
