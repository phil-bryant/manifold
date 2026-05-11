# Restore Database Requirements

## Scope

Applies to `99_restore_database.sh`.

R001  Statement: Run in strict shell mode with private-default file permissions.
Design: Use `umask 007` and `set -euo pipefail`.
Tests:
- Verify script exits on failing command and unset variable paths.

R005  Statement: Accept optional backup source path and support latest-backup defaulting.
Design: Parse `--from`; otherwise select newest `.dump` in local backups directory.
Tests:
- Run without args and verify newest dump is selected.
- Run with `--from` and verify provided path is selected.

R010  Statement: Require restore dependencies before restore operations.
Design: Validate `1psa`, `pg_restore`, and `psql` are available on PATH.
Tests:
- Remove `pg_restore` from PATH and verify clear failure.

R015  Statement: Resolve postgres password and target host/port from 1psa.
Design: Read postgres password via `1psa -p` default or `1psa -f` override field, then read `localhost_postgres_manifold` `host`/`port`/`database`/`schema` and validate non-empty/valid values.
Tests:
- Force empty password response and verify non-zero exit.

R020  Statement: Require dump and matching globals files before restore.
Design: Validate selected `.dump` path and require sibling `_globals.sql` file before running restore.
Tests:
- Run restore with missing globals file and verify restore is refused.

R025  Statement: Refuse restore when target database already contains ingest schema objects.
Design: Query target database and abort when `ingest_batches` already exists in the `1psa`-resolved target schema.
Tests:
- Restore into existing initialized db and verify refusal message.

R030  Statement: Restore globals before database content.
Design: Run globals SQL with `psql`, then run `pg_restore --clean --if-exists --create` against postgres.
Tests:
- Verify restore order is globals first, then database content.

R035  Statement: Print completion output with selected backup path.
Design: Emit final restore-complete message with selected dump file path after successful replay.
Tests:
- Verify successful run prints completion line with backup path.

## Changelog

- 2026-05-11: Read restore target schema name from `1psa` and scope ingest-table safety checks to that schema.
- 2026-05-11: Read restore target database name from `1psa` and remove hardcoded `public` schema assumptions.
- 2026-05-10: Reswizzled restore requirements from teller-specific scoped restore/credential sync logic to manifold full-restore flow.
- 2026-04-19: Initial reverse-engineered requirements for `99_restore_database.sh`.
