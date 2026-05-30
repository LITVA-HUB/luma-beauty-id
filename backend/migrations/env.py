from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# This project uses raw SQL DDL inside the migration scripts (the app talks to
# the database with hand-written SQL, not SQLAlchemy models), so there is no
# metadata to autogenerate against.
target_metadata = None


def _database_url() -> str:
    """Resolve the migration URL.

    Priority: an explicit ``sqlalchemy.url`` in alembic.ini (rare, mostly for
    ad-hoc runs) wins; otherwise fall back to the application's ``DATABASE_URL``
    so `alembic upgrade head` targets the same Postgres the app uses. The
    psycopg3 driver requires the ``postgresql+psycopg`` dialect prefix.
    """
    configured = config.get_main_option("sqlalchemy.url")
    if configured:
        return configured

    from app.config import settings

    url = settings.database_url
    if not url:
        raise RuntimeError(
            "DATABASE_URL is not set; alembic migrations target Postgres only"
        )
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    elif url.startswith("postgres://"):
        url = "postgresql+psycopg://" + url[len("postgres://"):]
    return url


def run_migrations_offline() -> None:
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    section = config.get_section(config.config_ini_section, {})
    section["sqlalchemy.url"] = _database_url()
    connectable = engine_from_config(
        section,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
