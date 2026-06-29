#Requires -Version 5.1
<#
.SYNOPSIS
  Duke's Bank JPA E2E: CMP->JPA apply, re-export, JPA crosswalk, parity-verify.

.DESCRIPTION
  Extends the baseline EJB E2E with ADR-004 Step 4d / ADR-007 SS3.3:
  1. Schema SSOT (reuse MySQL from demo-dukesbank)
  2. Export before (javaee-ejb2-jboss) -> dukesbank-code-before.db
  3. Copy bank tree, apply CmpScalarEntityToJpa to AccountBean.java
  4. Export after (auto-detect profiles) -> dukesbank-code-after.db
  5. Crosswalk before/after -> linked DBs
  6. parity-verify compare -> parity-report.json

.EXAMPLE
  .\scripts\run-e2e-jpa-parity.ps1
  .\scripts\run-e2e-jpa-parity.ps1 -SkipDocker
#>
param(
    [switch]$SkipDocker,
    [string]$GithubRoot = "C:\github"
)

$ErrorActionPreference = "Stop"

$AnchorRoot = Join-Path $GithubRoot "anchor-migration"
$DemoRoot = Join-Path $AnchorRoot "demo-dukesbank"
$DbMetaRoot = Join-Path $AnchorRoot "db-metadata"
$JavaAstRoot = Join-Path $AnchorRoot "java-ast-ssot"
$RewriteRoot = Join-Path $AnchorRoot "rewrite-recipes"
$ParityRoot = Join-Path $AnchorRoot "parity-verify"
$BankRoot = Join-Path $GithubRoot "dukesbank\src\j2eetutorial14\examples\bank"
$BankMount = ($BankRoot -replace '\\', '/') + ":/bank:ro"
$AccountBeanRel = "src/com/sun/ebank/ejb/account/AccountBean.java"

function Assert-PathExists([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) {
        throw "Missing $Label`: $Path"
    }
}

Assert-PathExists $BankRoot "Duke's Bank module"
Assert-PathExists (Join-Path $DbMetaRoot "pyproject.toml") "db-metadata"
Assert-PathExists (Join-Path $JavaAstRoot "pom.xml") "java-ast-ssot"
Assert-PathExists (Join-Path $RewriteRoot "pom.xml") "rewrite-recipes"
Assert-PathExists (Join-Path $ParityRoot "pom.xml") "parity-verify"

$MetaDir = Join-Path $JavaAstRoot "metadata"
New-Item -ItemType Directory -Force -Path $MetaDir | Out-Null
$WorkBank = Join-Path $env:TEMP "dukesbank-jpa-work"
if (Test-Path $WorkBank) {
    Remove-Item -Recurse -Force $WorkBank
}

Write-Host "==> Step 1: MySQL + schema SSOT" -ForegroundColor Cyan
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
}

Push-Location $DbMetaRoot
$jdbc = "mysql+pymysql://dukesbank:dukesbank@localhost:3306/dukesbank"
New-Item -ItemType Directory -Force -Path metadata | Out-Null
db-migration export --url $jdbc --out metadata/dukesbank.db
db-migration verify metadata/dukesbank.db --url $jdbc
Pop-Location

Write-Host "==> Step 2: Build tool JARs (Docker Maven)" -ForegroundColor Cyan
docker run --rm -v "C:/github/anchor-migration/java-ast-ssot:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests
docker run --rm -v "C:/github/anchor-migration/rewrite-recipes:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests
docker run --rm -v "C:/github/anchor-migration/parity-verify:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests

Write-Host "==> Step 3: Export BEFORE code SSOT (EJB profile)" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v $BankMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export `
    -s /bank --profile javaee-ejb2-jboss -o metadata/dukesbank-code-before.db

Write-Host "==> Step 4: Apply CmpScalarEntityToJpa to AccountBean" -ForegroundColor Cyan
Copy-Item -Recurse -Force $BankRoot $WorkBank
$AccountBeanPath = Join-Path $WorkBank $AccountBeanRel
Assert-PathExists $AccountBeanPath "AccountBean.java in work copy"
$WorkMount = ($WorkBank -replace '\\', '/') + ":/work"

docker run --rm `
    -v "C:/github/anchor-migration/rewrite-recipes:/app" `
    -v $WorkMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    bash -lc "mvn -B -q compile dependency:build-classpath -Dmdep.outputFile=target/cp.txt -Dmdep.includeScope=compile && java -cp target/classes:`$(cat target/cp.txt)` com.anchor.migration.rewrite.cli.ApplyRecipeMain CmpScalarEntityToJpa /work/$($AccountBeanRel -replace '\\','/')"

if (-not (Select-String -Path $AccountBeanPath -Pattern "@javax.persistence.Entity" -Quiet)) {
    throw "AccountBean.java was not transformed to JPA (@Entity missing)"
}

Write-Host "==> Step 5: Export AFTER code SSOT (auto-detect profiles)" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v $WorkMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export `
    -s /work --auto-detect-profiles -o metadata/dukesbank-code-after.db

Write-Host "==> Step 6: Crosswalk before / after" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v "C:/github/anchor-migration/db-metadata:/dbmeta:ro" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk `
    --code-db metadata/dukesbank-code-before.db `
    --schema-db /dbmeta/metadata/dukesbank.db `
    --db-schema dukesbank `
    -o metadata/dukesbank-linked-before.db

docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/app" `
    -v "C:/github/anchor-migration/db-metadata:/dbmeta:ro" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk `
    --code-db metadata/dukesbank-code-after.db `
    --schema-db /dbmeta/metadata/dukesbank.db `
    --db-schema dukesbank `
    -o metadata/dukesbank-linked-after.db

Write-Host "==> Step 7: parity-verify structural diff" -ForegroundColor Cyan
docker run --rm `
    -v "C:/github/anchor-migration/java-ast-ssot:/javassot" `
    -v "C:/github/anchor-migration/parity-verify:/app" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/parity-verify-0.1.0-SNAPSHOT.jar compare `
    --before-db /javassot/metadata/dukesbank-code-before.db `
    --after-db /javassot/metadata/dukesbank-code-after.db `
    --linked-before /javassot/metadata/dukesbank-linked-before.db `
    --linked-after /javassot/metadata/dukesbank-linked-after.db `
    -o metadata/dukesbank-parity-report.json

$parityReport = Join-Path $ParityRoot "metadata\dukesbank-parity-report.json"
Assert-PathExists $parityReport "parity report"

Write-Host ""
Write-Host "JPA E2E + parity complete." -ForegroundColor Green
Write-Host "  Before code:  $MetaDir\dukesbank-code-before.db"
Write-Host "  After code:   $MetaDir\dukesbank-code-after.db"
Write-Host "  Linked after: $MetaDir\dukesbank-linked-after.db"
Write-Host "  Parity JSON:  $parityReport"
Write-Host ""
Write-Host "Review parity-report.json — expect removals (EJB lifecycle / abstract CMP) and JPA field additions." -ForegroundColor Yellow
