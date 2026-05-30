from __future__ import annotations

import logging
from pathlib import Path

from ..config import settings

logger = logging.getLogger("luma.api.migrations")

# backend/app/storage/migrations.py -> parents[2] == backend/
_BACKEND_DIR = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_DIR / "alembic.ini"


def run_migrations_if_enabled() -> None:
    """Run `alembic upgrade head` on startup when explicitly enabled.

    Gated behind ``RUN_DB_MIGRATIONS`` and a Postgres ``DATABASE_URL``. SQLite
    and the test suite never reach Alembic — those rely on the store's runtime
    ``_init_db`` self-bootstrap. Failures are re-raised so a misconfigured
    production deploy fails loudly instead of serving against a stale schema.
    """
    if not settings.run_db_migrations:
        return
    if not settings.database_url:
        logger.warning("RUN_DB_MIGRATIONS is set but DATABASE_URL is empty; skipping migrations")
        return

    try:
        from alembic import command
        from alembic.config import Config
    except ImportError:  # pragma: no cover - alembic is a deploy-only dependency
        logger.error("RUN_DB_MIGRATIONS is set but alembic is not installed")
        raise

    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_BACKEND_DIR / "migrations"))
    logger.info("running alembic upgrade head")
    command.upgrade(cfg, "head")
    logger.info("alembic upgrade head complete")
