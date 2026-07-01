#Requires -Version 5.1
<#
.SYNOPSIS
  Duke's Bank multi-entity JPA E2E: CMP->JPA apply, re-export, crosswalk, parity-verify.

.DESCRIPTION
  ADR-007 v0.4 multi-entity slice on Duke's Bank bank module:
  1. Schema SSOT (MySQL via demo-dukesbank)
  2. Export BEFORE code SSOT (javaee-ejb2-jboss)
  3. Apply CMP->JPA recipes:
       AccountBean — CmpScalarEntityToJpa + CmpManyToManyToJpa
       CustomerBean — CmpScalarEntityToJpa
       TxBean — CmpScalarEntityToJpa + CmpForeignKeyToJpa
  4. Export AFTER (auto-detect profiles)
  5. Crosswalk before / after
  6. parity-verify per entity (pattern-catalog matrices)

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
$AnchorMount = ($AnchorRoot -replace '\\', '/')

$AccountBeanRel = "src/com/sun/ebank/ejb/account/AccountBean.java"
$CustomerBeanRel = "src/com/sun/ebank/ejb/customer/CustomerBean.java"
$TxBeanRel = "src/com/sun/ebank/ejb/tx/TxBean.java"

$NextIdBeanRel = "src/com/sun/ebank/ejb/util/NextIdBean.java"

$EntityMigrations = @(
    @{
        Label = "AccountBean"
        RelPath = $AccountBeanRel
        Steps = @(
            @{ Recipe = "CmpScalarEntityToJpa"; TargetClass = $null }
            @{ Recipe = "CmpManyToManyToJpa"; TargetClass = $null }
        )
        MustMatch = @(
            "@javax.persistence.Entity"
            "@javax.persistence.ManyToMany"
            "CUSTOMER_ACCOUNT_XREF"
        )
        MatrixFile = "examples/matrices/dukesbank-cmp-jpa-multi-account.yaml"
    }
    @{
        Label = "CustomerBean"
        RelPath = $CustomerBeanRel
        Steps = @(
            @{ Recipe = "CmpScalarEntityToJpa"; TargetClass = "CustomerBean" }
        )
        MustMatch = @(
            "@javax.persistence.Entity"
            '@javax.persistence.Table(name = "CUSTOMER")'
        )
        MatrixFile = "examples/matrices/dukesbank-cmp-jpa-multi-customer.yaml"
    }
    @{
        Label = "TxBean"
        RelPath = $TxBeanRel
        Steps = @(
            @{ Recipe = "CmpScalarEntityToJpa"; TargetClass = "TxBean" }
            @{ Recipe = "CmpForeignKeyToJpa"; TargetClass = $null }
        )
        MustMatch = @(
            "@javax.persistence.Entity"
            "@javax.persistence.ManyToOne"
            "account_id"
        )
        MatrixFile = "examples/matrices/dukesbank-cmp-jpa-multi-tx.yaml"
    }
    @{
        Label = "NextIdBean"
        RelPath = $NextIdBeanRel
        Steps = @(
            @{ Recipe = "NextIdTableToJpa"; TargetClass = $null }
        )
        MustMatch = @(
            "@javax.persistence.Entity"
            "getNextId()"
        )
        MatrixFile = "examples/matrices/dukesbank-cmp-jpa-multi-nextid.yaml"
    }
)

function Assert-PathExists([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) {
        throw "Missing $Label`: $Path"
    }
}

function Invoke-ApplyRecipe {
    param(
        [string]$WorkMount,
        [string]$RelPath,
        [string]$Recipe,
        [string]$TargetClass
    )
    $linuxPath = "/work/$($RelPath -replace '\\','/')"
    $javaArgs = "com.anchor.migration.rewrite.cli.ApplyRecipeMain $Recipe $linuxPath"
    if ($TargetClass) {
        $javaArgs += " $TargetClass"
    }
    docker run --rm `
        -v "${AnchorMount}/rewrite-recipes:/app" `
        -v $WorkMount `
        -w /app maven:3.9-eclipse-temurin-17 `
        bash -lc "set -e; mvn -B -q compile dependency:build-classpath -Dmdep.outputFile=target/cp.txt -Dmdep.includeScope=compile && java -cp target/classes:`$(cat target/cp.txt)` $javaArgs"
}

function Invoke-ParityMatrix {
    param(
        [string]$WorkMount,
        [string]$RelPath,
        [string]$MatrixFile,
        [string]$ReportBaseName
    )
    $touchpoint = "/work/$($RelPath -replace '\\','/')"
    $parityArgs = @(
        'compare',
        '--before-db', '/javassot/metadata/dukesbank-code-before.db',
        '--after-db', '/javassot/metadata/dukesbank-code-after.db',
        '--linked-before', '/javassot/metadata/dukesbank-linked-before.db',
        '--linked-after', '/javassot/metadata/dukesbank-linked-after.db',
        '--matrix-file', $MatrixFile,
        '--touchpoint-source', $touchpoint,
        '-o', "metadata/$ReportBaseName.json",
        '--html-out', "metadata/$ReportBaseName.html",
        '--fail-on-matrix'
    )
    docker run --rm `
        -v "${AnchorMount}/java-ast-ssot:/javassot" `
        -v "${AnchorMount}/parity-verify:/app" `
        -v $WorkMount `
        -w /app maven:3.9-eclipse-temurin-17 `
        java -jar target/parity-verify-0.2.0-SNAPSHOT.jar @parityArgs
    if ($LASTEXITCODE -ne 0) {
        throw "parity-verify failed for $ReportBaseName (exit $LASTEXITCODE)"
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
if ($LASTEXITCODE -ne 0) { throw "db-migration export failed (exit $LASTEXITCODE)" }
db-migration verify metadata/dukesbank.db --url $jdbc
if ($LASTEXITCODE -ne 0) { throw "db-migration verify failed (exit $LASTEXITCODE)" }
Pop-Location

Write-Host "==> Step 2: Build tool JARs (Docker Maven)" -ForegroundColor Cyan
docker run --rm -v "${AnchorMount}/java-ast-ssot:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests
docker run --rm -v "${AnchorMount}/rewrite-recipes:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests
docker run --rm -v "${AnchorMount}/parity-verify:/app" -w /app `
    maven:3.9-eclipse-temurin-17 mvn -B -q package -DskipTests

Write-Host "==> Step 3: Export BEFORE code SSOT (EJB profile)" -ForegroundColor Cyan
docker run --rm `
    -v "${AnchorMount}/java-ast-ssot:/app" `
    -v $BankMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export `
    -s /bank --profile javaee-ejb2-jboss -o metadata/dukesbank-code-before.db

Write-Host "==> Step 4: Apply CMP->JPA recipes (multi-entity)" -ForegroundColor Cyan
Copy-Item -Recurse -Force $BankRoot $WorkBank
$WorkMount = ($WorkBank -replace '\\', '/') + ":/work"

foreach ($entity in $EntityMigrations) {
    $filePath = Join-Path $WorkBank $entity.RelPath
    Assert-PathExists $filePath "$($entity.Label).java in work copy"
    Write-Host "  --- $($entity.Label) ---" -ForegroundColor DarkCyan
    foreach ($step in $entity.Steps) {
        $target = if ($step.TargetClass) { $step.TargetClass } else { $null }
        Write-Host "    $($step.Recipe)$(if ($target) { " ($target)" })"
        Invoke-ApplyRecipe -WorkMount $WorkMount -RelPath $entity.RelPath -Recipe $step.Recipe -TargetClass $target
    }
    foreach ($pattern in $entity.MustMatch) {
        if (-not (Select-String -Path $filePath -Pattern ([regex]::Escape($pattern)) -Quiet)) {
            throw "$($entity.Label).java missing expected pattern: $pattern"
        }
    }
    Write-Host "    OK: $($entity.Label) transform verified" -ForegroundColor Green
}

Write-Host "==> Step 5: Export AFTER code SSOT (auto-detect profiles)" -ForegroundColor Cyan
docker run --rm `
    -v "${AnchorMount}/java-ast-ssot:/app" `
    -v $WorkMount `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar export `
    -s /work --auto-detect-profiles -o metadata/dukesbank-code-after.db

Write-Host "==> Step 6: Crosswalk before / after" -ForegroundColor Cyan
docker run --rm `
    -v "${AnchorMount}/java-ast-ssot:/app" `
    -v "${AnchorMount}/db-metadata:/dbmeta:ro" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk `
    --code-db metadata/dukesbank-code-before.db `
    --schema-db /dbmeta/metadata/dukesbank.db `
    --db-schema dukesbank `
    -o metadata/dukesbank-linked-before.db

docker run --rm `
    -v "${AnchorMount}/java-ast-ssot:/app" `
    -v "${AnchorMount}/db-metadata:/dbmeta:ro" `
    -w /app maven:3.9-eclipse-temurin-17 `
    java -jar target/java-ast-ssot-1.0.0-SNAPSHOT.jar crosswalk `
    --code-db metadata/dukesbank-code-after.db `
    --schema-db /dbmeta/metadata/dukesbank.db `
    --db-schema dukesbank `
    -o metadata/dukesbank-linked-after.db

Write-Host "==> Step 7: parity-verify behavioral matrices (per entity)" -ForegroundColor Cyan
$ParityReports = @()
foreach ($entity in $EntityMigrations) {
    $reportBase = "dukesbank-parity-$($entity.Label.ToLower())"
    Write-Host "  --- matrix: $($entity.MatrixFile) ---" -ForegroundColor DarkCyan
    Invoke-ParityMatrix -WorkMount $WorkMount -RelPath $entity.RelPath -MatrixFile $entity.MatrixFile -ReportBaseName $reportBase
    $jsonPath = Join-Path $ParityRoot "metadata\$reportBase.json"
    $htmlPath = Join-Path $ParityRoot "metadata\$reportBase.html"
    Assert-PathExists $jsonPath "parity report $reportBase"
    Assert-PathExists $htmlPath "parity HTML $reportBase"
    $ParityReports += @{ Label = $entity.Label; Json = $jsonPath; Html = $htmlPath }
}

Write-Host ""
Write-Host "Multi-entity JPA E2E + parity complete." -ForegroundColor Green
Write-Host "  Before code:  $MetaDir\dukesbank-code-before.db"
Write-Host "  After code:   $MetaDir\dukesbank-code-after.db"
Write-Host "  Linked after: $MetaDir\dukesbank-linked-after.db"
foreach ($report in $ParityReports) {
    Write-Host "  Parity $($report.Label) JSON:  $($report.Json)"
    Write-Host "  Parity $($report.Label) HTML:  $($report.Html)"
}
Write-Host ""
Write-Host "All entity matrices passed (--fail-on-matrix). Review HTML reports for structural drift details." -ForegroundColor Yellow
