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

    $seedSql = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "db/migrations/007_seed_reference_data.sql")
    $seedSql | docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $testDatabase --set ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Reference seed rerun failed" }

    $testSql = Get-Content -Raw -LiteralPath (Join-Path $projectRoot "tests/database/foundation.sql")
    $testSql | docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $testDatabase --set ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "Foundation assertions failed" }

    $migrationCount = docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $testDatabase --tuples-only --no-align `
        --command "SELECT count(*) FROM schema_migrations;"
    if ($LASTEXITCODE -ne 0 -or $migrationCount.Trim() -ne "7") {
        throw "Expected 7 applied migrations, got '$($migrationCount.Trim())'"
    }

    Write-Host "PASS: empty database migration, migration rerun, direct seed rerun, and foundation constraints."
}
finally {
    docker compose --project-directory $projectRoot exec -T postgres dropdb `
        --username $dbUser --force $testDatabase
}
