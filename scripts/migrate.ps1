param(
    [string]$Database = $(if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { "themis" })
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$migrationDir = Join-Path $projectRoot "db/migrations"
$dbUser = if ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "themis" }

function Invoke-Psql([string]$Sql) {
    $Sql | docker compose --project-directory $projectRoot exec -T postgres psql `
        --username $dbUser --dbname $Database --set ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "psql failed with exit code $LASTEXITCODE" }
}

Invoke-Psql @"
CREATE TABLE IF NOT EXISTS schema_migrations (
    version text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);
"@

$appliedText = docker compose --project-directory $projectRoot exec -T postgres psql `
    --username $dbUser --dbname $Database --tuples-only --no-align `
    --command "SELECT version FROM schema_migrations ORDER BY version;"
if ($LASTEXITCODE -ne 0) { throw "Could not read schema_migrations" }
$applied = @($appliedText | ForEach-Object { $_.Trim() } | Where-Object { $_ })

Get-ChildItem -LiteralPath $migrationDir -Filter "*.sql" | Sort-Object Name | ForEach-Object {
    if ($applied -contains $_.Name) {
        Write-Host "SKIP  $($_.Name)"
        return
    }

    Write-Host "APPLY $($_.Name)"
    $escapedName = $_.Name.Replace("'", "''")
    $body = Get-Content -Raw -LiteralPath $_.FullName
    Invoke-Psql "BEGIN;`n$body`nINSERT INTO schema_migrations(version) VALUES ('$escapedName');`nCOMMIT;"
}

Write-Host "Migrations complete for database '$Database'."

