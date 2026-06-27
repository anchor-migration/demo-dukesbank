#Requires -Version 5.1
<#
.SYNOPSIS
  Duke's Bank end-to-end: MySQL -> schema SSOT -> code SSOT -> crosswalk -> linked.db

.DESCRIPTION
  Assumes sibling layout:
    C:\github\anchor-migration\  (this script lives under demo-dukesbank\scripts\)
    C:\github\dukesbank\

  Does NOT start anchor-explorer — after success, run:
    cd ..\anchor-explorer && npm run dev
  Then load: java-ast-ssot\metadata\dukesbank-linked.db

.EXAMPLE
  .\scripts\run-e2e.ps1
  .\scripts\run-e2e.ps1 -SkipDocker   # MySQL already running
#>
param(
    [switch]$SkipDocker,
    [string]$GithubRoot = "C:\github",
    [string]$BankMount = ""
)

$ErrorActionPreference = "Stop"

$AnchorRoot = Join-Path $GithubRoot "anchor-migration"
$DemoRoot = Join-Path $AnchorRoot "demo-dukesbank"
$DbMetaRoot = Join-Path $AnchorRoot "db-metadata"
$JavaAstRoot = Join-Path $AnchorRoot "java-ast-ssot"
$BankRoot = Join-Path $GithubRoot "dukesbank\src\j2eetutorial14\examples\bank"

if (-not $BankMount) {
    $BankMount = ($BankRoot -replace '\\', '/') + ":/bank:ro"
}

function Assert-PathExists([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) {
        throw "Missing $Label`: $Path"
    }
}

Assert-PathExists $BankRoot "Duke's Bank module (clone dukesbank next to anchor-migration)"
Assert-PathExists (Join-Path $DbMetaRoot "pyproject.toml") "db-metadata repo"
Assert-PathExists (Join-Path $JavaAstRoot "pom.xml") "java-ast-ssot repo"

Write-Host "==> Step 1: MySQL (demo-dukesbank)" -ForegroundColor Cyan
if (-not $SkipDocker) {
    Push-Location $DemoRoot
    docker compose up -d
    $deadline = (Get-Date).AddMinutes(3)
    do {
        Start-Sleep -Seconds 3
        $status = docker inspect -f "{{.State.Health.Status}}" dukesbank-mysql 2>$null
        Write-Host "  health: $status"
    } while ($status -ne "healthy" -and (Get-Date) -lt $deadline)
    if ($status -ne "healthy") { throw "MySQL container not healthy" }
    Pop-Location
} else {
    Write-Host "  skipped (-SkipDocker)"
}

Write-Host "==> Step 2: Schema SSOT (db-metadata)" -ForegroundColor Cyan
Push-Location $DbMetaRoot
$jdbc = "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank"
New-Item -ItemType Directory -Force -Path metadata | Out-Null
db-migration export --url $jdbc --out metadata/dukesbank.db
db-migration verify metadata/dukesbank.db --url $jdbc
Pop-Location

Write-Host "==> Step 3: Build java-ast-ssot (Docker Maven)" -ForegroundColor Cyan
docker run --rm -v "C:/github/anchor-migration/java-ast-ssot:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests

Write-Host "==> Step 4: Code SSOT export" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v $BankMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export `
    -s /bank --profile javaee-ejb2-jboss -o metadata/dukesbank-code.db

Write-Host "==> Step 5: Crosswalk -> linked SSOT" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v "C:/github/anchor-migration/db-metadata:/dbmeta:ro" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk `
    --code-db metadata/dukesbank-code.db `
    --schema-db /dbmeta/metadata/dukesbank.db `
    --db-schema dukesbank `
    -o metadata/dukesbank-linked.db

$linked = Join-Path $JavaAstRoot "metadata\dukesbank-linked.db"
Assert-PathExists $linked "linked SSOT"

Write-Host ""
Write-Host "E2E complete." -ForegroundColor Green
Write-Host "  Linked SSOT: $linked"
Write-Host ""
Write-Host "Next — Anchor Explorer:" -ForegroundColor Yellow
Write-Host "  cd $AnchorRoot\anchor-explorer"
Write-Host "  npm run dev"
Write-Host "  Open http://127.0.0.1:5173/ and load the linked.db file above"
Write-Host "  Expected: 32 links, 0 issues"
