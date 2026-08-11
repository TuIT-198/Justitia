# Implementation Status

## Current Phase

Foundation Phase 01 — PostgreSQL project setup and foundational schema. Complete and runtime-verified.

## DONE

- Inspected repository; it initially contained only `PROMPT_01_THEMIS_FOUNDATION.md`.
- Selected PostgreSQL 17 and ordered plain-SQL migrations executed through containerized `psql`.
- Added Docker Compose local PostgreSQL setup and non-secret environment template.
- Implemented Identity schema with optional local credentials and hashed-token storage fields.
- Implemented Organization and system RBAC schema with multiple roles per member.
- Implemented countries, markets, products, varieties, forms, HS nomenclatures, HS codes, and product mappings.
- Added database constraints, composite tenant-safe member FK, and lookup indexes.
- Added idempotent seeds for system roles/permissions, Vietnam, China, CN_GACC, durian, and requested product forms.
- Added an isolated database foundation test harness.
- Documented schema, current ERD, migration workflow, database inspection, and local reset.
- Verified Docker Compose configuration and a healthy local PostgreSQL container.
- Verified all seven migrations from an empty database, migration rerun behavior, direct seed rerun safety, and foundation constraints.

## IN_PROGRESS

- None.

## TODO

- None within Prompt 01.
- Later prompts may add RLS after the tenant schema stabilizes.

## BLOCKED

- None currently.

## Important Decisions

- Use plain SQL migrations tracked in `schema_migrations`; no application stack exists yet to justify an ORM-specific migration framework.
- Keep roles system-defined; tenant custom roles are deferred.
- Carry `organization_id` into `organization_member_roles` and enforce a composite FK to prevent cross-tenant member-role linkage.
- Do not seed any HS classification, MRL, or legal/compliance data without an official verified source.
- Keep all post-foundation modules explicitly out of scope.
