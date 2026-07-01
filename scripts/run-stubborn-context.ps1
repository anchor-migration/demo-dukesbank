#Requires -Version 5.1
<#
.SYNOPSIS
  Docker-first wrapper for run-stubborn-context.sh (stubborn Step 7).

.EXAMPLE
  .\scripts\run-stubborn-context.ps1
#>
$ErrorActionPreference = "Stop"
$DemoRoot = Split-Path -Parent $PSScriptRoot
$GitBash = @(
    "${env:ProgramFiles}\Git\bin\bash.exe"
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($GitBash) {
    & $GitBash -lc "cd '$(($DemoRoot -replace '\\','/'))' && ./scripts/run-stubborn-context.sh"
    exit $LASTEXITCODE
}

Push-Location $DemoRoot
try {
    bash ./scripts/run-stubborn-context.sh
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
