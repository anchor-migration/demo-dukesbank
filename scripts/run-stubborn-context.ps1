#Requires -Version 5.1
<#
.SYNOPSIS
  Duke's Bank Step 7 — scip-java + anchor-stubborn context for AccountControllerBean.

.DESCRIPTION
  Delegates to anchor-stubborn/examples/dukesbank/scripts/run-e2e.ps1
  Requires dukesbank clone as sibling of anchor-migration.

.EXAMPLE
  .\scripts\run-stubborn-context.ps1
#>
param(
    [string]$BankRoot = ""
)

$ErrorActionPreference = "Stop"

$DemoRoot = Split-Path -Parent $PSScriptRoot
$AnchorRoot = Join-Path (Split-Path -Parent $DemoRoot) "anchor-stubborn"
$StubbornScript = Join-Path $AnchorRoot "examples\dukesbank\scripts\run-e2e.ps1"

if (-not (Test-Path $StubbornScript)) {
    throw "anchor-stubborn not found at $AnchorRoot — clone anchor-migration workspace."
}

$params = @{}
if ($BankRoot) { $params["BankRoot"] = $BankRoot }

& $StubbornScript @params
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n==> verify neighbors..." -ForegroundColor Cyan
Push-Location $AnchorRoot
python scripts\verify_dukesbank_context.py
$code = $LASTEXITCODE
Pop-Location
exit $code
