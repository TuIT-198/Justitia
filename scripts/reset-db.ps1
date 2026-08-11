param(
    [string]$Database = $(if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "themis" })
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "themis" }

"DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;" |
    docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $Database --set ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "Database reset failed" }

Write-Host "Database '$Database' reset. Run scripts/migrate.ps1 next."

