"""initial schema

Canonical Postgres schema for Luma Beauty ID. This mirrors the DDL that
``PostgresStore._init_db`` creates at runtime. Both paths use ``IF NOT EXISTS``
so they coexist safely: Alembic is the source of truth for managed Postgres
deployments, while the runtime self-init remains the fallback for local SQLite
and first-boot safety.

Revision ID: 001_initial_schema
Revises:
Create Date: 2026-05-30
"""
from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision = "001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts(
    account_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    phone_number_e164 TEXT UNIQUE,
    password_hash TEXT NOT NULL DEFAULT '',
    is_guest BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions(
    session_id TEXT PRIMARY KEY,
    access_token TEXT NOT NULL UNIQUE,
    refresh_token TEXT NOT NULL UNIQUE,
    account_id TEXT NOT NULL,
    access_expires_at TEXT NOT NULL,
    refresh_expires_at TEXT NOT NULL,
    dev_mode INTEGER NOT NULL DEFAULT 0,
    revoked_at TEXT
);
CREATE TABLE IF NOT EXISTS beauty_ids(
    account_id TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS carts(
    account_id TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS histories(
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    payload TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS advisor_messages(
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    recommended_skus TEXT NOT NULL DEFAULT '[]',
    provider TEXT,
    prompt_version TEXT,
    safety_note TEXT,
    fallback_reason TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS saved_routines(
    account_id TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS active_selections(
    account_id TEXT PRIMARY KEY,
    payload TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS feedback(
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    rating INTEGER NOT NULL,
    message TEXT NOT NULL,
    context TEXT,
    app_version TEXT,
    build TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS privacy_requests(
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS events(
    id TEXT PRIMARY KEY,
    account_id TEXT,
    event_name TEXT NOT NULL,
    payload TEXT NOT NULL,
    app_version TEXT,
    build TEXT,
    platform TEXT,
    created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS advisor_runs(
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    prompt_version TEXT,
    provider TEXT,
    model TEXT,
    latency_ms INTEGER,
    fallback_reason TEXT,
    invalid_json INTEGER NOT NULL DEFAULT 0,
    unknown_sku_count INTEGER NOT NULL DEFAULT 0,
    medical_refusal INTEGER NOT NULL DEFAULT 0,
    allowed_products_count INTEGER NOT NULL DEFAULT 0,
    recommended_skus_count INTEGER NOT NULL DEFAULT 0,
    action_count INTEGER NOT NULL DEFAULT 0,
    request_id TEXT,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_histories_account_kind ON histories(account_id, kind, created_at);
CREATE INDEX IF NOT EXISTS idx_advisor_messages_account_created ON advisor_messages(account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_feedback_account_created ON feedback(account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_events_account_created ON events(account_id, created_at);
CREATE INDEX IF NOT EXISTS idx_events_name_created ON events(event_name, created_at);
CREATE INDEX IF NOT EXISTS idx_advisor_runs_account_created ON advisor_runs(account_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_phone ON accounts(phone_number_e164);
"""


_TABLES = (
    "advisor_runs",
    "events",
    "privacy_requests",
    "feedback",
    "active_selections",
    "saved_routines",
    "advisor_messages",
    "histories",
    "carts",
    "beauty_ids",
    "sessions",
    "accounts",
)


def upgrade() -> None:
    op.execute(SCHEMA)


def downgrade() -> None:
    for table in _TABLES:
        op.execute(f"DROP TABLE IF EXISTS {table} CASCADE")
