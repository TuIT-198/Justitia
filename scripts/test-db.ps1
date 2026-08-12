$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "themis" }
$testDatabase = "themis_foundation_test"

$exists = docker compose --project-directory $projectRoot exec -T postgres psql `
    --username $dbUser --dbname postgres --tuples-only --no-align `
    --command "SELECT 1 FROM pg_database WHERE datname = '$testDatabase';"
if ($LASTEXITCODE -ne 0) { throw "Could not inspect test database" }

if ($null -ne $exists -and "$exists".Trim() -eq "1") {
    docker compose --project-directory $projectRoot exec -T postgres dropdb `
        --username $dbUser --force $testDatabase
    if ($LASTEXITCODE -ne 0) { throw "Could not drop prior test database" }
}

docker compose --project-directory $projectRoot exec -T postgres createdb `
    --username $dbUser $testDatabase
if ($LASTEXITCODE -ne 0) { throw "Could not create empty test database" }

try {
    & (Join-Path $PSScriptRoot "migrate.ps1") -Database $testDatabase
    & (Join-Path $PSScriptRoot "migrate.ps1") -Database $testDatabase

    Get-ChildItem -LiteralPath (Join-Path $projectRoot "db/migrations") -Filter "*seed*.sql" |
        Sort-Object Name | ForEach-Object {
            Write-Host "SEED  $($_.Name)"
            $seedSql = Get-Content -Raw -LiteralPath $_.FullName
            $seedSql | docker compose --project-directory $projectRoot exec -T postgres psql `
                --username $dbUser --dbname $testDatabase --set ON_ERROR_STOP=1
            if ($LASTEXITCODE -ne 0) { throw "Reference seed rerun failed: $($_.Name)" }
        }

    Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests/database") -Filter "*.sql" |
        Sort-Object Name | ForEach-Object {
            Write-Host "TEST  $($_.Name)"
            $testSql = Get-Content -Raw -LiteralPath $_.FullName
            $testSql | docker compose --project-directory $projectRoot exec -T postgres psql `
                --username $dbUser --dbname $testDatabase --set ON_ERROR_STOP=1
            if ($LASTEXITCODE -ne 0) { throw "Database assertions failed: $($_.Name)" }
        }

    Get-ChildItem -LiteralPath (Join-Path $projectRoot "tests/security") -Filter "*.sql" |
        Sort-Object Name | ForEach-Object {
            Write-Host "SECURITY  $($_.Name)"
            $testSql = Get-Content -Raw -LiteralPath $_.FullName
            $testSql | docker compose --project-directory $projectRoot exec -T postgres psql `
                --username $dbUser --dbname $testDatabase --set ON_ERROR_STOP=1
            if ($LASTEXITCODE -ne 0) { throw "Security/RLS assertions failed: $($_.Name)" }
        }

    $migrationCount = docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $testDatabase --tuples-only --no-align `
        --command "SELECT count(*) FROM schema_migrations;"
    $expectedMigrationCount = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "db/migrations") -Filter "*.sql").Count
    if ($LASTEXITCODE -ne 0 -or [int]$migrationCount.Trim() -ne $expectedMigrationCount) {
        throw "Expected $expectedMigrationCount applied migrations, got '$($migrationCount.Trim())'"
    }

    Write-Host "PASS: empty database migration, migration rerun, all seed reruns, Phase 01-09 database regressions, and Phase 10 RLS/security tests."
}
finally {
    docker compose --project-directory $projectRoot exec -T postgres dropdb `
        --username $dbUser --force $testDatabase
}
