# Themis LexiGuard

Database foundation for Themis LexiGuard. This phase contains PostgreSQL schema and reference data only; application, OCR, legal knowledge, AI, and compliance modules are intentionally not implemented yet.

## Prerequisites

- Docker Desktop with Docker Compose
- PowerShell 7 or Windows PowerShell 5.1

Copy `.env.example` to `.env` and choose a local-only password. Never commit `.env`.

## Local PostgreSQL

Start PostgreSQL and wait for the health check:

```powershell
docker compose up -d --wait postgres
```

Run all pending migrations and idempotent reference seeds:

```powershell
./scripts/migrate.ps1
```

Inspect the database:

```powershell
docker compose exec postgres psql -U themis -d themis
```

Useful commands inside `psql` include `\dt`, `\d users`, and `SELECT * FROM schema_migrations ORDER BY version;`.

Run the database foundation tests against a disposable database:

```powershell
./scripts/test-db.ps1
```

Reset the local database schema, then rebuild it:

```powershell
./scripts/reset-db.ps1
./scripts/migrate.ps1
```

The reset command drops the `public` schema in the selected local database. It is destructive and must not be pointed at a shared or production database.

Stop PostgreSQL while retaining data:

```powershell
docker compose down
```

## Migration policy

Migrations in `db/migrations` are applied lexicographically and recorded in `schema_migrations`. Never edit a migration after it has been applied outside local development; add a new numbered migration instead. Migration `007_seed_reference_data.sql` uses upserts and is safe to execute again. No unverified HS codes, MRLs, or other legal data are seeded.

