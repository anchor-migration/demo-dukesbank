#Requires -Version 5.1
<#
.SYNOPSIS
  Docker-first wrapper for run-e2e.sh (schema -> code -> crosswalk).

.EXAMPLE
  .\scripts\run-e2e.ps1
  .\scripts\run-e2e.ps1 -SkipDocker
#>
param(
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
$DemoRoot = Split-Path -Parent $PSScriptRoot
$BashScript = Join-Path $PSScriptRoot "run-e2e.sh"

if ($SkipDocker) { $env:SKIP_DOCKER = "1" } else { Remove-Item Env:SKIP_DOCKER -ErrorAction SilentlyContinue }

# Prefer Git Bash on Windows; fall back to docker compose directly.
$GitBash = @(
    "${env:ProgramFiles}\Git\bin\bash.exe"
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($GitBash) {
    & $GitBash -lc "cd '$(($DemoRoot -replace '\\','/'))' && ./scripts/run-e2e.sh"
    exit $LASTEXITCODE
}

Push-Location $DemoRoot
try {
    if (-not $SkipDocker) {
        docker compose up -d mysql
        $deadline = (Get-Date).AddMinutes(3)
        do {
            Start-Sleep -Seconds 3
            $status = docker inspect -f "{{.State.Health.Status}}" dukesbank-mysql 2>$null
            Write-Host "  health: $status"
        } while ($status -ne "healthy" -and (Get-Date) -lt $deadline)
        if ($status -ne "healthy") { throw "MySQL container not healthy" }
    }
    docker compose build runner
    docker compose run --rm e2e
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
