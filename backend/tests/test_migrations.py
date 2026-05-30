"""Guard tests for the Alembic integration.

These do not spin up Postgres; they verify the startup runner stays inert
unless explicitly enabled, and that the initial revision is well-formed.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

from app.config import settings
from app.storage.migrations import run_migrations_if_enabled

_MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "migrations"
    / "versions"
    / "001_initial_schema.py"
)


def test_runner_is_noop_when_disabled(monkeypatch):
    # Default test config keeps migrations off; calling the runner must not
    # touch Alembic or raise even when a DATABASE_URL is present.
    monkeypatch.setattr(settings, "run_db_migrations", False)
    monkeypatch.setattr(settings, "database_url", "postgresql://u:p@localhost/db")
    assert run_migrations_if_enabled() is None


def test_runner_skips_when_no_database_url(monkeypatch):
    monkeypatch.setattr(settings, "run_db_migrations", True)
    monkeypatch.setattr(settings, "database_url", "")
    # No DATABASE_URL => warns and returns without invoking Alembic.
    assert run_migrations_if_enabled() is None


def test_initial_revision_is_well_formed():
    spec = importlib.util.spec_from_file_location("initial_schema", _MIGRATION)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.revision == "001_initial_schema"
    assert module.down_revision is None
    assert hasattr(module, "upgrade")
    assert hasattr(module, "downgrade")
    # Every table created in upgrade must be dropped on downgrade.
    assert "accounts" in module._TABLES
    assert "advisor_runs" in module._TABLES
