# Database migrations (Alembic)

Postgres deployments are managed with [Alembic](https://alembic.sqlalchemy.org/).
Alembic is the source of truth for the production/staging schema; local SQLite
runs and the test suite keep using the store's runtime `_init_db` self-bootstrap
and never touch Alembic.

## Layout

| Path | Purpose |
| --- | --- |
| `backend/alembic.ini` | Alembic config. `sqlalchemy.url` is intentionally blank. |
| `backend/migrations/env.py` | Resolves the URL from the app's `DATABASE_URL`. |
| `backend/migrations/versions/001_initial_schema.py` | Initial schema, ported from `PostgresStore._init_db`. |

`env.py` reads `DATABASE_URL` from `app.config.settings` and rewrites the
`postgresql://` (or `postgres://`) prefix to `postgresql+psycopg://` so the
psycopg3 driver is used. Setting `sqlalchemy.url` in `alembic.ini` overrides this
and is only meant for ad-hoc manual runs against a throwaway database.

## Running migrations

### Automatically on startup (recommended for managed deploys)

The app calls `run_migrations_if_enabled()` (in
`backend/app/storage/migrations.py`) before creating the store. It runs
`alembic upgrade head` only when **both**:

- `RUN_DB_MIGRATIONS=true`, and
- `DATABASE_URL` is set (Postgres).

Failures are re-raised so a misconfigured deploy fails loudly instead of serving
against a stale schema. The flag defaults to **off**, so SQLite/dev and CI are
unaffected.

```sh
export DATABASE_URL="postgresql://user:pass@host:5432/luma"
export RUN_DB_MIGRATIONS=true
python3 -m app.main   # runs `alembic upgrade head`, then boots the API
```

### Manually from the CLI

```sh
cd backend
export DATABASE_URL="postgresql://user:pass@host:5432/luma"
python3 -m alembic upgrade head        # apply
python3 -m alembic downgrade -1        # roll back one revision
python3 -m alembic current             # show applied revision
python3 -m alembic upgrade head --sql  # print SQL without connecting (offline)
```

## Why `CREATE TABLE IF NOT EXISTS`

Both the migration and the runtime `_init_db` use `IF NOT EXISTS`, so the two
paths coexist safely. A database that was first created by the runtime
bootstrap can later be brought under Alembic control with:

```sh
python3 -m alembic stamp head   # mark the existing schema as already migrated
```

## Adding a new migration

```sh
cd backend
export DATABASE_URL="postgresql://user:pass@host:5432/luma"
python3 -m alembic revision -m "add_xyz_column"
# edit the generated file in migrations/versions/, then:
python3 -m alembic upgrade head
```

The project uses hand-written SQL (`op.execute(...)`) rather than SQLAlchemy
models, so autogenerate is not wired up — write the DDL explicitly and provide a
matching `downgrade()`.
