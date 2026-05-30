from __future__ import annotations

import json
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from threading import Lock
from typing import Any

from .config import settings
from .schemas import AccountPublic, AdvisorHistoryMessage, BeautyID, CartItem, CartResponse, Product
from .security import expires_in_days, expires_in_minutes, hash_password, make_token, utcnow, verify_password

INTERNAL_HISTORY_MARKERS = (
    "Контекст предыдущего диалога",
    "Новое сообщение пользователя",
    "Ответь именно",
    "allowed_products",
    "system prompt",
    "developer message",
    "internal context",
    "prompt_version",
    "JSON schema",
    "Ты ассистент",
    "You are",
)


def _looks_like_internal_prompt(text: str) -> bool:
    lower = text.lower()
    return any(marker.lower() in lower for marker in INTERNAL_HISTORY_MARKERS)


def normalize_phone_e164(value: str | None) -> str | None:
    """Best-effort E.164 normalization (no carrier lookup / SMS verification)."""
    if value is None:
        return None
    raw = value.strip()
    if not raw:
        return None
    digits = "".join(ch for ch in raw if ch.isdigit())
    if not digits:
        return None
    # Russian local "8XXXXXXXXXX" → "+7XXXXXXXXXX".
    if not raw.startswith("+") and len(digits) == 11 and digits[0] == "8":
        digits = "7" + digits[1:]
    if not 8 <= len(digits) <= 15:
        raise ValueError("invalid_phone")
    return "+" + digits


@dataclass(frozen=True)
class StoredAccount:
    account_id: str
    name: str
    email: str | None
    password_hash: str
    created_at: datetime
    phone_number_e164: str | None = None
    is_guest: bool = False

    @property
    def has_password(self) -> bool:
        return bool(self.password_hash)

    def public(self) -> AccountPublic:
        return AccountPublic(
            account_id=self.account_id,
            name=self.name,
            email=self.email,
            phone_number=self.phone_number_e164,
            is_guest=self.is_guest,
            created_at=self.created_at,
        )


@dataclass(frozen=True)
class StoredSession:
    session_id: str
    access_token: str
    refresh_token: str
    account_id: str
    access_expires_at: datetime
    refresh_expires_at: datetime
    dev_mode: bool = False
    revoked_at: datetime | None = None

    @property
    def is_revoked(self) -> bool:
        return self.revoked_at is not None


class SQLiteAppStore:
    def __init__(self, path: str | None = None) -> None:
        self.path = path or settings.store_path
        if self.path != ":memory:":
            Path(self.path).parent.mkdir(parents=True, exist_ok=True)
        self._lock = Lock()
        self._init_db()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, detect_types=sqlite3.PARSE_DECLTYPES, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._connect() as db:
            db.executescript(
                """
                CREATE TABLE IF NOT EXISTS accounts(
                    account_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE,
                    phone_number_e164 TEXT UNIQUE,
                    password_hash TEXT NOT NULL DEFAULT '',
                    is_guest INTEGER NOT NULL DEFAULT 0,
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
                """
            )
            columns = {row[1] for row in db.execute("PRAGMA table_info(sessions)").fetchall()}
            expected = {"session_id", "access_token", "refresh_token", "access_expires_at", "refresh_expires_at", "revoked_at"}
            if not expected.issubset(columns):
                db.execute("DROP TABLE IF EXISTS sessions")
                db.executescript(
                    """
                    CREATE TABLE sessions(
                        session_id TEXT PRIMARY KEY,
                        access_token TEXT NOT NULL UNIQUE,
                        refresh_token TEXT NOT NULL UNIQUE,
                        account_id TEXT NOT NULL,
                        access_expires_at TEXT NOT NULL,
                        refresh_expires_at TEXT NOT NULL,
                        dev_mode INTEGER NOT NULL DEFAULT 0,
                        revoked_at TEXT
                    );
                    """
                )
            self._migrate_accounts(db)

    def _migrate_accounts(self, db: sqlite3.Connection) -> None:
        info = db.execute("PRAGMA table_info(accounts)").fetchall()
        columns = {row[1] for row in info}
        if "phone_number_e164" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN phone_number_e164 TEXT")
            db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_phone ON accounts(phone_number_e164)")
        if "is_guest" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN is_guest INTEGER NOT NULL DEFAULT 0")
        # Relax the legacy NOT NULL on email so phone-only / guest accounts can exist.
        email_notnull = any(row[1] == "email" and row[3] == 1 for row in info)
        if email_notnull:
            db.execute("ALTER TABLE accounts RENAME TO accounts_legacy")
            db.execute(
                """
                CREATE TABLE accounts(
                    account_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    email TEXT UNIQUE,
                    phone_number_e164 TEXT UNIQUE,
                    password_hash TEXT NOT NULL DEFAULT '',
                    is_guest INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                )
                """
            )
            db.execute(
                "INSERT INTO accounts(account_id,name,email,phone_number_e164,password_hash,is_guest,created_at) "
                "SELECT account_id,name,email,phone_number_e164,password_hash,is_guest,created_at FROM accounts_legacy"
            )
            db.execute("DROP TABLE accounts_legacy")
            db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_phone ON accounts(phone_number_e164)")

    def stats(self) -> dict[str, Any]:
        with self._connect() as db:
            accounts = db.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            sessions = db.execute("SELECT COUNT(*) FROM sessions WHERE revoked_at IS NULL").fetchone()[0]
        return {"accounts": accounts, "active_sessions": sessions, "path": self.path}

    def create_account(
        self,
        name: str,
        email: str | None = None,
        password: str | None = None,
        *,
        phone: str | None = None,
        is_guest: bool = False,
    ) -> StoredAccount:
        account = StoredAccount(
            account_id=("guest_" + uuid.uuid4().hex[:8]) if is_guest else str(uuid.uuid4()),
            name=name.strip(),
            email=email.strip().lower() if email else None,
            password_hash=hash_password(password) if password else "",
            created_at=utcnow(),
            phone_number_e164=normalize_phone_e164(phone),
            is_guest=is_guest,
        )
        with self._lock, self._connect() as db:
            try:
                db.execute(
                    "INSERT INTO accounts(account_id,name,email,phone_number_e164,password_hash,is_guest,created_at) "
                    "VALUES(?,?,?,?,?,?,?)",
                    (
                        account.account_id,
                        account.name,
                        account.email,
                        account.phone_number_e164,
                        account.password_hash,
                        1 if account.is_guest else 0,
                        account.created_at.isoformat(),
                    ),
                )
            except sqlite3.IntegrityError as exc:
                raise ValueError("account_exists") from exc
        return account

    def create_guest_account(self, name: str = "Гость") -> StoredAccount:
        return self.create_account(name, is_guest=True)

    def attach_phone(
        self, account_id: str, phone: str, *, name: str | None = None, password: str | None = None
    ) -> StoredAccount | None:
        normalized = normalize_phone_e164(phone)
        with self._lock, self._connect() as db:
            sets = ["phone_number_e164=?", "is_guest=0"]
            params: list[Any] = [normalized]
            if name and name.strip():
                sets.append("name=?")
                params.append(name.strip())
            if password:
                sets.append("password_hash=?")
                params.append(hash_password(password))
            params.append(account_id)
            try:
                db.execute(f"UPDATE accounts SET {', '.join(sets)} WHERE account_id=?", params)
            except sqlite3.IntegrityError as exc:
                raise ValueError("phone_taken") from exc
        return self.get_account(account_id)

    def ensure_dev_account(self) -> StoredAccount:
        account = self.get_account_by_email("development@luma.local")
        if account:
            return account
        return self.create_account("Development Client", "development@luma.local", "development-password")

    def get_account_by_email(self, email: str) -> StoredAccount | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM accounts WHERE email=?", (email.strip().lower(),)).fetchone()
        return self._row_to_account(row) if row else None

    def get_account_by_phone(self, phone: str) -> StoredAccount | None:
        normalized = normalize_phone_e164(phone)
        if not normalized:
            return None
        with self._connect() as db:
            row = db.execute("SELECT * FROM accounts WHERE phone_number_e164=?", (normalized,)).fetchone()
        return self._row_to_account(row) if row else None

    def get_account(self, account_id: str) -> StoredAccount | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM accounts WHERE account_id=?", (account_id,)).fetchone()
        return self._row_to_account(row) if row else None

    def authenticate(self, email: str, password: str) -> StoredAccount | None:
        account = self.get_account_by_email(email)
        if account and verify_password(password, account.password_hash):
            return account
        return None

    def authenticate_by_phone(self, phone: str, password: str | None) -> StoredAccount | None:
        account = self.get_account_by_phone(phone)
        if not account:
            return None
        # Passwordless accounts log in by phone alone; password-protected ones must match.
        if not account.has_password:
            return account
        if password and verify_password(password, account.password_hash):
            return account
        return None

    def _row_to_account(self, row: sqlite3.Row) -> StoredAccount:
        keys = row.keys()
        return StoredAccount(
            account_id=row["account_id"],
            name=row["name"],
            email=row["email"],
            password_hash=row["password_hash"],
            created_at=datetime.fromisoformat(row["created_at"]),
            phone_number_e164=row["phone_number_e164"] if "phone_number_e164" in keys else None,
            is_guest=bool(row["is_guest"]) if "is_guest" in keys else False,
        )

    def create_session(self, account_id: str, dev_mode: bool = False) -> StoredSession:
        session = StoredSession(
            session_id=str(uuid.uuid4()),
            access_token=make_token("acc"),
            refresh_token=make_token("ref"),
            account_id=account_id,
            access_expires_at=expires_in_minutes(settings.access_token_ttl_minutes),
            refresh_expires_at=expires_in_days(settings.refresh_token_ttl_days),
            dev_mode=dev_mode,
        )
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO sessions(session_id,access_token,refresh_token,account_id,access_expires_at,refresh_expires_at,dev_mode,revoked_at) VALUES(?,?,?,?,?,?,?,?)",
                (
                    session.session_id,
                    session.access_token,
                    session.refresh_token,
                    session.account_id,
                    session.access_expires_at.isoformat(),
                    session.refresh_expires_at.isoformat(),
                    1 if dev_mode else 0,
                    None,
                ),
            )
        return session

    def _row_to_session(self, row: sqlite3.Row) -> StoredSession:
        return StoredSession(
            session_id=row["session_id"],
            access_token=row["access_token"],
            refresh_token=row["refresh_token"],
            account_id=row["account_id"],
            access_expires_at=datetime.fromisoformat(row["access_expires_at"]),
            refresh_expires_at=datetime.fromisoformat(row["refresh_expires_at"]),
            dev_mode=bool(row["dev_mode"]),
            revoked_at=datetime.fromisoformat(row["revoked_at"]) if row["revoked_at"] else None,
        )

    def get_session_by_access(self, access_token: str) -> StoredSession | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM sessions WHERE access_token=?", (access_token,)).fetchone()
        if not row:
            return None
        session = self._row_to_session(row)
        if session.is_revoked or session.access_expires_at < utcnow():
            return None
        return session

    def get_session_by_refresh(self, refresh_token: str) -> StoredSession | None:
        with self._connect() as db:
            row = db.execute("SELECT * FROM sessions WHERE refresh_token=?", (refresh_token,)).fetchone()
        if not row:
            return None
        session = self._row_to_session(row)
        if session.is_revoked or session.refresh_expires_at < utcnow():
            return None
        return session

    def refresh_session(self, refresh_token: str) -> StoredSession | None:
        existing = self.get_session_by_refresh(refresh_token)
        if not existing:
            return None
        new_session = StoredSession(
            session_id=existing.session_id,
            access_token=make_token("acc"),
            refresh_token=make_token("ref"),
            account_id=existing.account_id,
            access_expires_at=expires_in_minutes(settings.access_token_ttl_minutes),
            refresh_expires_at=expires_in_days(settings.refresh_token_ttl_days),
            dev_mode=existing.dev_mode,
        )
        with self._lock, self._connect() as db:
            db.execute(
                "UPDATE sessions SET access_token=?, refresh_token=?, access_expires_at=?, refresh_expires_at=?, revoked_at=NULL WHERE session_id=?",
                (
                    new_session.access_token,
                    new_session.refresh_token,
                    new_session.access_expires_at.isoformat(),
                    new_session.refresh_expires_at.isoformat(),
                    existing.session_id,
                ),
            )
        return new_session

    def revoke_by_access(self, access_token: str) -> None:
        with self._lock, self._connect() as db:
            db.execute("UPDATE sessions SET revoked_at=? WHERE access_token=?", (utcnow().isoformat(), access_token))

    def revoke_by_refresh(self, refresh_token: str) -> None:
        with self._lock, self._connect() as db:
            db.execute("UPDATE sessions SET revoked_at=? WHERE refresh_token=?", (utcnow().isoformat(), refresh_token))

    def save_beauty_id(self, account_id: str, beauty_id: BeautyID) -> BeautyID:
        saved = beauty_id.model_copy(update={"updated_at": utcnow()})
        payload = saved.model_dump_json()
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO beauty_ids(account_id,payload,updated_at) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                (account_id, payload, saved.updated_at.isoformat()),
            )
        return saved

    def get_beauty_id(self, account_id: str) -> BeautyID | None:
        with self._connect() as db:
            row = db.execute("SELECT payload FROM beauty_ids WHERE account_id=?", (account_id,)).fetchone()
        return BeautyID.model_validate_json(row["payload"]) if row else None

    def get_cart_quantities(self, account_id: str) -> dict[str, int]:
        with self._connect() as db:
            row = db.execute("SELECT payload FROM carts WHERE account_id=?", (account_id,)).fetchone()
        if not row:
            return {}
        data = json.loads(row["payload"])
        return {str(k): int(v) for k, v in data.items() if int(v) > 0}

    def save_cart(self, account_id: str, quantities: dict[str, int]) -> None:
        payload = json.dumps({sku: qty for sku, qty in quantities.items() if qty > 0})
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO carts(account_id,payload,updated_at) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                (account_id, payload, utcnow().isoformat()),
            )

    def save_saved_routine(self, account_id: str, skus: list[str]) -> tuple[list[str], datetime]:
        updated_at = utcnow()
        payload = json.dumps(skus)
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO saved_routines(account_id,payload,updated_at) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                (account_id, payload, updated_at.isoformat()),
            )
        return skus, updated_at

    def get_saved_routine(self, account_id: str) -> tuple[list[str], datetime] | None:
        with self._connect() as db:
            row = db.execute("SELECT payload,updated_at FROM saved_routines WHERE account_id=?", (account_id,)).fetchone()
        if not row:
            return None
        raw = json.loads(row["payload"])
        skus = [str(item).strip().upper() for item in raw if str(item).strip()]
        return skus, datetime.fromisoformat(row["updated_at"])

    def clear_saved_routine(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            db.execute("DELETE FROM saved_routines WHERE account_id=?", (account_id,))

    def save_active_selection(self, account_id: str, items: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], datetime]:
        updated_at = utcnow()
        payload = json.dumps(items)
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO active_selections(account_id,payload,updated_at) VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                (account_id, payload, updated_at.isoformat()),
            )
        return items, updated_at

    def get_active_selection(self, account_id: str) -> tuple[list[dict[str, Any]], datetime] | None:
        with self._connect() as db:
            row = db.execute("SELECT payload,updated_at FROM active_selections WHERE account_id=?", (account_id,)).fetchone()
        if not row:
            return None
        data = json.loads(row["payload"] or "[]")
        return list(data) if isinstance(data, list) else [], datetime.fromisoformat(row["updated_at"])

    def clear_active_selection(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            db.execute("DELETE FROM active_selections WHERE account_id=?", (account_id,))

    def add_feedback(
        self,
        account_id: str,
        rating: int,
        message: str,
        context: str | None = None,
        app_version: str | None = None,
        build: str | None = None,
    ) -> tuple[str, datetime]:
        feedback_id = str(uuid.uuid4())
        created_at = utcnow()
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO feedback(id,account_id,rating,message,context,app_version,build,created_at) VALUES(?,?,?,?,?,?,?,?)",
                (feedback_id, account_id, rating, message.strip(), context, app_version, build, created_at.isoformat()),
            )
        return feedback_id, created_at

    def add_event(
        self,
        account_id: str | None,
        event_name: str,
        payload: dict[str, Any] | None = None,
        app_version: str | None = None,
        build: str | None = None,
        platform: str | None = None,
    ) -> tuple[str, datetime]:
        event_id = str(uuid.uuid4())
        created_at = utcnow()
        safe_payload = {key: value for key, value in (payload or {}).items() if key not in {"raw_message", "message", "photo_b64", "raw_photo", "image_bytes", "access_token", "refresh_token"}}
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO events(id,account_id,event_name,payload,app_version,build,platform,created_at) VALUES(?,?,?,?,?,?,?,?)",
                (event_id, account_id, event_name.strip().lower(), json.dumps(safe_payload), app_version, build, platform, created_at.isoformat()),
            )
        return event_id, created_at

    def add_advisor_run(self, account_id: str, payload: dict[str, Any]) -> str:
        run_id = str(uuid.uuid4())
        created_at = utcnow()
        with self._lock, self._connect() as db:
            db.execute(
                """
                INSERT INTO advisor_runs(
                    id,account_id,prompt_version,provider,model,latency_ms,fallback_reason,invalid_json,unknown_sku_count,
                    medical_refusal,allowed_products_count,recommended_skus_count,action_count,request_id,created_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    run_id,
                    account_id,
                    payload.get("prompt_version"),
                    payload.get("provider"),
                    payload.get("model"),
                    int(payload.get("latency_ms") or 0),
                    payload.get("fallback_reason"),
                    1 if payload.get("invalid_json") else 0,
                    int(payload.get("unknown_sku_count") or 0),
                    1 if payload.get("medical_refusal") else 0,
                    int(payload.get("allowed_products_count") or 0),
                    int(payload.get("recommended_skus_count") or 0),
                    int(payload.get("action_count") or 0),
                    payload.get("request_id"),
                    created_at.isoformat(),
                ),
            )
        return run_id

    def add_history(self, kind: str, account_id: str, payload: dict[str, Any]) -> None:
        safe_payload = {key: value for key, value in payload.items() if key not in {"photo_b64", "raw_photo", "image_bytes"}}
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO histories(id,account_id,kind,payload,created_at) VALUES(?,?,?,?,?)",
                (str(uuid.uuid4()), account_id, kind, json.dumps(safe_payload), utcnow().isoformat()),
            )

    def list_history(self, kind: str, account_id: str, limit: int = 20) -> list[dict[str, Any]]:
        with self._connect() as db:
            rows = db.execute(
                "SELECT payload,created_at FROM histories WHERE account_id=? AND kind=? ORDER BY created_at DESC LIMIT ?",
                (account_id, kind, limit),
            ).fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            payload = json.loads(row["payload"])
            payload["created_at"] = row["created_at"]
            out.append(payload)
        return out

    def add_advisor_message(
        self,
        account_id: str,
        role: str,
        content: str,
        recommended_skus: list[str] | None = None,
        provider: str | None = None,
        prompt_version: str | None = None,
        safety_note: str | None = None,
        fallback_reason: str | None = None,
    ) -> AdvisorHistoryMessage:
        message = AdvisorHistoryMessage(
            id=f"msg_{uuid.uuid4().hex}",
            role=role,  # type: ignore[arg-type]
            content=content,
            recommended_skus=recommended_skus or [],
            provider=provider,
            prompt_version=prompt_version,
            safety_note=safety_note,
            fallback_reason=fallback_reason,
            created_at=utcnow(),
        )
        safe_content = content.strip()
        with self._lock, self._connect() as db:
            db.execute(
                """
                INSERT INTO advisor_messages(id,account_id,role,content,recommended_skus,provider,prompt_version,safety_note,fallback_reason,created_at)
                VALUES(?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    message.id,
                    account_id,
                    message.role,
                    safe_content,
                    json.dumps(message.recommended_skus),
                    message.provider,
                    message.prompt_version,
                    message.safety_note,
                    message.fallback_reason,
                    message.created_at.isoformat(),
                ),
            )
        return message.model_copy(update={"content": safe_content})

    def list_advisor_messages(self, account_id: str, limit: int = 100) -> list[AdvisorHistoryMessage]:
        with self._connect() as db:
            rows = db.execute(
                """
                SELECT id,role,content,recommended_skus,provider,prompt_version,safety_note,fallback_reason,created_at
                FROM advisor_messages
                WHERE account_id=?
                ORDER BY created_at ASC
                LIMIT ?
                """,
                (account_id, limit),
            ).fetchall()
        return [
            AdvisorHistoryMessage(
                id=row["id"],
                role=row["role"],
                content=row["content"],
                recommended_skus=json.loads(row["recommended_skus"] or "[]"),
                provider=row["provider"],
                prompt_version=row["prompt_version"],
                safety_note=row["safety_note"],
                fallback_reason=row["fallback_reason"],
                created_at=datetime.fromisoformat(row["created_at"]),
            )
            for row in rows
            if not _looks_like_internal_prompt(row["content"])
        ]

    def clear_advisor_messages(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            db.execute("DELETE FROM advisor_messages WHERE account_id=?", (account_id,))

    def create_privacy_request(self, account_id: str, kind: str) -> str:
        request_id = str(uuid.uuid4())
        with self._lock, self._connect() as db:
            db.execute(
                "INSERT INTO privacy_requests(id,account_id,kind,status,created_at) VALUES(?,?,?,?,?)",
                (request_id, account_id, kind, "accepted", utcnow().isoformat()),
            )
        return request_id

    def export_user_data(self, account_id: str, products_by_sku: dict[str, Product]) -> dict[str, Any]:
        return {
            "beauty_id": self.get_beauty_id(account_id),
            "cart": cart_response_from_quantities(self.get_cart_quantities(account_id), products_by_sku),
            "histories": {
                "recommendations": self.list_history("recommendation_history", account_id),
                "scans": self.list_history("scan_history", account_id),
                "advisor": self.list_history("advisor_history", account_id),
            },
            "saved_routine": self.get_saved_routine(account_id),
            "advisor_messages": [message.model_dump() for message in self.list_advisor_messages(account_id)],
        }


AppStore = SQLiteAppStore


def cart_response_from_quantities(quantities: dict[str, int], products_by_sku: dict[str, Product], checkout_mode: str = "unavailable") -> CartResponse:
    items: list[CartItem] = []
    for sku, quantity in quantities.items():
        product = products_by_sku.get(sku)
        if product:
            items.append(CartItem(sku=sku, product=product, quantity=quantity))
    subtotal = sum(item.product.price_value * item.quantity for item in items if item.product.availability)
    total_items = sum(item.quantity for item in items)
    return CartResponse(items=items, total_items=total_items, subtotal=subtotal, checkout_mode=checkout_mode)  # type: ignore[arg-type]


class PostgresStore:
    def __init__(self, database_url: str) -> None:
        self.database_url = database_url
        self._lock = Lock()
        self._init_db()

    def _connect(self):
        import psycopg
        from psycopg.rows import dict_row

        return psycopg.connect(self.database_url, row_factory=dict_row)

    def _init_db(self) -> None:
        schema = """
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
        """
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute(schema)
                cur.execute("ALTER TABLE accounts ADD COLUMN IF NOT EXISTS phone_number_e164 TEXT")
                cur.execute("ALTER TABLE accounts ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE")
                cur.execute("ALTER TABLE accounts ALTER COLUMN email DROP NOT NULL")
                cur.execute("ALTER TABLE accounts ALTER COLUMN password_hash SET DEFAULT ''")
                cur.execute(
                    "CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_phone ON accounts(phone_number_e164)"
                )

    def stats(self) -> dict[str, Any]:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT COUNT(*) AS count FROM accounts")
                accounts = cur.fetchone()["count"]
                cur.execute("SELECT COUNT(*) AS count FROM sessions WHERE revoked_at IS NULL")
                sessions = cur.fetchone()["count"]
        return {"accounts": accounts, "active_sessions": sessions, "driver": "postgresql"}

    def create_account(
        self,
        name: str,
        email: str | None = None,
        password: str | None = None,
        *,
        phone: str | None = None,
        is_guest: bool = False,
    ) -> StoredAccount:
        account = StoredAccount(
            account_id=("guest_" + uuid.uuid4().hex[:8]) if is_guest else str(uuid.uuid4()),
            name=name.strip(),
            email=email.strip().lower() if email else None,
            password_hash=hash_password(password) if password else "",
            created_at=utcnow(),
            phone_number_e164=normalize_phone_e164(phone),
            is_guest=is_guest,
        )
        with self._lock, self._connect() as db:
            try:
                with db.cursor() as cur:
                    cur.execute(
                        "INSERT INTO accounts(account_id,name,email,phone_number_e164,password_hash,is_guest,created_at) "
                        "VALUES(%s,%s,%s,%s,%s,%s,%s)",
                        (
                            account.account_id,
                            account.name,
                            account.email,
                            account.phone_number_e164,
                            account.password_hash,
                            account.is_guest,
                            account.created_at.isoformat(),
                        ),
                    )
            except Exception as exc:
                if getattr(exc, "sqlstate", "") == "23505":
                    raise ValueError("account_exists") from exc
                raise
        return account

    def create_guest_account(self, name: str = "Гость") -> StoredAccount:
        return self.create_account(name, is_guest=True)

    def attach_phone(
        self, account_id: str, phone: str, *, name: str | None = None, password: str | None = None
    ) -> StoredAccount | None:
        normalized = normalize_phone_e164(phone)
        sets = ["phone_number_e164=%s", "is_guest=FALSE"]
        params: list[Any] = [normalized]
        if name and name.strip():
            sets.append("name=%s")
            params.append(name.strip())
        if password:
            sets.append("password_hash=%s")
            params.append(hash_password(password))
        params.append(account_id)
        with self._lock, self._connect() as db:
            try:
                with db.cursor() as cur:
                    cur.execute(f"UPDATE accounts SET {', '.join(sets)} WHERE account_id=%s", params)
            except Exception as exc:
                if getattr(exc, "sqlstate", "") == "23505":
                    raise ValueError("phone_taken") from exc
                raise
        return self.get_account(account_id)

    def ensure_dev_account(self) -> StoredAccount:
        account = self.get_account_by_email("development@luma.local")
        if account:
            return account
        return self.create_account("Development Client", "development@luma.local", "development-password")

    def get_account_by_email(self, email: str) -> StoredAccount | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT * FROM accounts WHERE email=%s", (email.strip().lower(),))
                row = cur.fetchone()
        return self._row_to_account(row) if row else None

    def get_account_by_phone(self, phone: str) -> StoredAccount | None:
        normalized = normalize_phone_e164(phone)
        if not normalized:
            return None
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT * FROM accounts WHERE phone_number_e164=%s", (normalized,))
                row = cur.fetchone()
        return self._row_to_account(row) if row else None

    def get_account(self, account_id: str) -> StoredAccount | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT * FROM accounts WHERE account_id=%s", (account_id,))
                row = cur.fetchone()
        return self._row_to_account(row) if row else None

    def authenticate(self, email: str, password: str) -> StoredAccount | None:
        account = self.get_account_by_email(email)
        if account and verify_password(password, account.password_hash):
            return account
        return None

    def authenticate_by_phone(self, phone: str, password: str | None) -> StoredAccount | None:
        account = self.get_account_by_phone(phone)
        if not account:
            return None
        if not account.has_password:
            return account
        if password and verify_password(password, account.password_hash):
            return account
        return None

    def _row_to_account(self, row: dict[str, Any]) -> StoredAccount:
        return StoredAccount(
            account_id=row["account_id"],
            name=row["name"],
            email=row.get("email"),
            password_hash=row["password_hash"],
            created_at=datetime.fromisoformat(row["created_at"]),
            phone_number_e164=row.get("phone_number_e164"),
            is_guest=bool(row.get("is_guest", False)),
        )

    def create_session(self, account_id: str, dev_mode: bool = False) -> StoredSession:
        session = StoredSession(
            session_id=str(uuid.uuid4()),
            access_token=make_token("acc"),
            refresh_token=make_token("ref"),
            account_id=account_id,
            access_expires_at=expires_in_minutes(settings.access_token_ttl_minutes),
            refresh_expires_at=expires_in_days(settings.refresh_token_ttl_days),
            dev_mode=dev_mode,
        )
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO sessions(session_id,access_token,refresh_token,account_id,access_expires_at,refresh_expires_at,dev_mode,revoked_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)",
                    (
                        session.session_id,
                        session.access_token,
                        session.refresh_token,
                        session.account_id,
                        session.access_expires_at.isoformat(),
                        session.refresh_expires_at.isoformat(),
                        1 if dev_mode else 0,
                        None,
                    ),
                )
        return session

    def _row_to_session(self, row: dict[str, Any]) -> StoredSession:
        return StoredSession(
            session_id=row["session_id"],
            access_token=row["access_token"],
            refresh_token=row["refresh_token"],
            account_id=row["account_id"],
            access_expires_at=datetime.fromisoformat(row["access_expires_at"]),
            refresh_expires_at=datetime.fromisoformat(row["refresh_expires_at"]),
            dev_mode=bool(row["dev_mode"]),
            revoked_at=datetime.fromisoformat(row["revoked_at"]) if row["revoked_at"] else None,
        )

    def get_session_by_access(self, access_token: str) -> StoredSession | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT * FROM sessions WHERE access_token=%s", (access_token,))
                row = cur.fetchone()
        if not row:
            return None
        session = self._row_to_session(row)
        if session.is_revoked or session.access_expires_at < utcnow():
            return None
        return session

    def get_session_by_refresh(self, refresh_token: str) -> StoredSession | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT * FROM sessions WHERE refresh_token=%s", (refresh_token,))
                row = cur.fetchone()
        if not row:
            return None
        session = self._row_to_session(row)
        if session.is_revoked or session.refresh_expires_at < utcnow():
            return None
        return session

    def refresh_session(self, refresh_token: str) -> StoredSession | None:
        existing = self.get_session_by_refresh(refresh_token)
        if not existing:
            return None
        new_session = StoredSession(
            session_id=existing.session_id,
            access_token=make_token("acc"),
            refresh_token=make_token("ref"),
            account_id=existing.account_id,
            access_expires_at=expires_in_minutes(settings.access_token_ttl_minutes),
            refresh_expires_at=expires_in_days(settings.refresh_token_ttl_days),
            dev_mode=existing.dev_mode,
        )
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "UPDATE sessions SET access_token=%s, refresh_token=%s, access_expires_at=%s, refresh_expires_at=%s, revoked_at=NULL WHERE session_id=%s",
                    (
                        new_session.access_token,
                        new_session.refresh_token,
                        new_session.access_expires_at.isoformat(),
                        new_session.refresh_expires_at.isoformat(),
                        existing.session_id,
                    ),
                )
        return new_session

    def revoke_by_access(self, access_token: str) -> None:
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute("UPDATE sessions SET revoked_at=%s WHERE access_token=%s", (utcnow().isoformat(), access_token))

    def revoke_by_refresh(self, refresh_token: str) -> None:
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute("UPDATE sessions SET revoked_at=%s WHERE refresh_token=%s", (utcnow().isoformat(), refresh_token))

    def save_beauty_id(self, account_id: str, beauty_id: BeautyID) -> BeautyID:
        saved = beauty_id.model_copy(update={"updated_at": utcnow()})
        payload = saved.model_dump_json()
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO beauty_ids(account_id,payload,updated_at) VALUES(%s,%s,%s) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                    (account_id, payload, saved.updated_at.isoformat()),
                )
        return saved

    def get_beauty_id(self, account_id: str) -> BeautyID | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT payload FROM beauty_ids WHERE account_id=%s", (account_id,))
                row = cur.fetchone()
        return BeautyID.model_validate_json(row["payload"]) if row else None

    def get_cart_quantities(self, account_id: str) -> dict[str, int]:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT payload FROM carts WHERE account_id=%s", (account_id,))
                row = cur.fetchone()
        if not row:
            return {}
        data = json.loads(row["payload"])
        return {str(k): int(v) for k, v in data.items() if int(v) > 0}

    def save_cart(self, account_id: str, quantities: dict[str, int]) -> None:
        payload = json.dumps({sku: qty for sku, qty in quantities.items() if qty > 0})
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO carts(account_id,payload,updated_at) VALUES(%s,%s,%s) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                    (account_id, payload, utcnow().isoformat()),
                )

    def save_saved_routine(self, account_id: str, skus: list[str]) -> tuple[list[str], datetime]:
        updated_at = utcnow()
        payload = json.dumps(skus)
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO saved_routines(account_id,payload,updated_at) VALUES(%s,%s,%s) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                    (account_id, payload, updated_at.isoformat()),
                )
        return skus, updated_at

    def get_saved_routine(self, account_id: str) -> tuple[list[str], datetime] | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT payload,updated_at FROM saved_routines WHERE account_id=%s", (account_id,))
                row = cur.fetchone()
        if not row:
            return None
        raw = json.loads(row["payload"])
        skus = [str(item).strip().upper() for item in raw if str(item).strip()]
        return skus, datetime.fromisoformat(row["updated_at"])

    def clear_saved_routine(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute("DELETE FROM saved_routines WHERE account_id=%s", (account_id,))

    def save_active_selection(self, account_id: str, items: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], datetime]:
        updated_at = utcnow()
        payload = json.dumps(items)
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO active_selections(account_id,payload,updated_at) VALUES(%s,%s,%s) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at",
                    (account_id, payload, updated_at.isoformat()),
                )
        return items, updated_at

    def get_active_selection(self, account_id: str) -> tuple[list[dict[str, Any]], datetime] | None:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute("SELECT payload,updated_at FROM active_selections WHERE account_id=%s", (account_id,))
                row = cur.fetchone()
        if not row:
            return None
        raw = row["payload"]
        data = json.loads(raw) if isinstance(raw, str) else raw
        return list(data) if isinstance(data, list) else [], datetime.fromisoformat(row["updated_at"])

    def clear_active_selection(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute("DELETE FROM active_selections WHERE account_id=%s", (account_id,))

    def add_feedback(
        self,
        account_id: str,
        rating: int,
        message: str,
        context: str | None = None,
        app_version: str | None = None,
        build: str | None = None,
    ) -> tuple[str, datetime]:
        feedback_id = str(uuid.uuid4())
        created_at = utcnow()
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO feedback(id,account_id,rating,message,context,app_version,build,created_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)",
                        (feedback_id, account_id, rating, message.strip(), context, app_version, build, created_at.isoformat()),
                    )
        return feedback_id, created_at

    def add_event(
        self,
        account_id: str | None,
        event_name: str,
        payload: dict[str, Any] | None = None,
        app_version: str | None = None,
        build: str | None = None,
        platform: str | None = None,
    ) -> tuple[str, datetime]:
        event_id = str(uuid.uuid4())
        created_at = utcnow()
        safe_payload = {key: value for key, value in (payload or {}).items() if key not in {"raw_message", "message", "photo_b64", "raw_photo", "image_bytes", "access_token", "refresh_token"}}
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO events(id,account_id,event_name,payload,app_version,build,platform,created_at) VALUES(%s,%s,%s,%s,%s,%s,%s,%s)",
                    (event_id, account_id, event_name.strip().lower(), json.dumps(safe_payload), app_version, build, platform, created_at.isoformat()),
                )
        return event_id, created_at

    def add_advisor_run(self, account_id: str, payload: dict[str, Any]) -> str:
        run_id = str(uuid.uuid4())
        created_at = utcnow()
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO advisor_runs(
                        id,account_id,prompt_version,provider,model,latency_ms,fallback_reason,invalid_json,unknown_sku_count,
                        medical_refusal,allowed_products_count,recommended_skus_count,action_count,request_id,created_at
                    ) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        run_id,
                        account_id,
                        payload.get("prompt_version"),
                        payload.get("provider"),
                        payload.get("model"),
                        int(payload.get("latency_ms") or 0),
                        payload.get("fallback_reason"),
                        1 if payload.get("invalid_json") else 0,
                        int(payload.get("unknown_sku_count") or 0),
                        1 if payload.get("medical_refusal") else 0,
                        int(payload.get("allowed_products_count") or 0),
                        int(payload.get("recommended_skus_count") or 0),
                        int(payload.get("action_count") or 0),
                        payload.get("request_id"),
                        created_at.isoformat(),
                    ),
                )
        return run_id

    def add_history(self, kind: str, account_id: str, payload: dict[str, Any]) -> None:
        safe_payload = {key: value for key, value in payload.items() if key not in {"photo_b64", "raw_photo", "image_bytes"}}
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO histories(id,account_id,kind,payload,created_at) VALUES(%s,%s,%s,%s,%s)",
                    (str(uuid.uuid4()), account_id, kind, json.dumps(safe_payload), utcnow().isoformat()),
                )

    def list_history(self, kind: str, account_id: str, limit: int = 20) -> list[dict[str, Any]]:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "SELECT payload,created_at FROM histories WHERE account_id=%s AND kind=%s ORDER BY created_at DESC LIMIT %s",
                    (account_id, kind, limit),
                )
                rows = cur.fetchall()
        out: list[dict[str, Any]] = []
        for row in rows:
            payload = json.loads(row["payload"])
            payload["created_at"] = row["created_at"]
            out.append(payload)
        return out

    def add_advisor_message(
        self,
        account_id: str,
        role: str,
        content: str,
        recommended_skus: list[str] | None = None,
        provider: str | None = None,
        prompt_version: str | None = None,
        safety_note: str | None = None,
        fallback_reason: str | None = None,
    ) -> AdvisorHistoryMessage:
        message = AdvisorHistoryMessage(
            id=f"msg_{uuid.uuid4().hex}",
            role=role,  # type: ignore[arg-type]
            content=content,
            recommended_skus=recommended_skus or [],
            provider=provider,
            prompt_version=prompt_version,
            safety_note=safety_note,
            fallback_reason=fallback_reason,
            created_at=utcnow(),
        )
        safe_content = content.strip()
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO advisor_messages(id,account_id,role,content,recommended_skus,provider,prompt_version,safety_note,fallback_reason,created_at)
                    VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        message.id,
                        account_id,
                        message.role,
                        safe_content,
                        json.dumps(message.recommended_skus),
                        message.provider,
                        message.prompt_version,
                        message.safety_note,
                        message.fallback_reason,
                        message.created_at.isoformat(),
                    ),
                )
        return message.model_copy(update={"content": safe_content})

    def list_advisor_messages(self, account_id: str, limit: int = 100) -> list[AdvisorHistoryMessage]:
        with self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    """
                    SELECT id,role,content,recommended_skus,provider,prompt_version,safety_note,fallback_reason,created_at
                    FROM advisor_messages
                    WHERE account_id=%s
                    ORDER BY created_at ASC
                    LIMIT %s
                    """,
                    (account_id, limit),
                )
                rows = cur.fetchall()
        return [
            AdvisorHistoryMessage(
                id=row["id"],
                role=row["role"],
                content=row["content"],
                recommended_skus=json.loads(row["recommended_skus"] or "[]"),
                provider=row["provider"],
                prompt_version=row["prompt_version"],
                safety_note=row["safety_note"],
                fallback_reason=row["fallback_reason"],
                created_at=datetime.fromisoformat(row["created_at"]),
            )
            for row in rows
            if not _looks_like_internal_prompt(row["content"])
        ]

    def clear_advisor_messages(self, account_id: str) -> None:
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute("DELETE FROM advisor_messages WHERE account_id=%s", (account_id,))

    def create_privacy_request(self, account_id: str, kind: str) -> str:
        request_id = str(uuid.uuid4())
        with self._lock, self._connect() as db:
            with db.cursor() as cur:
                cur.execute(
                    "INSERT INTO privacy_requests(id,account_id,kind,status,created_at) VALUES(%s,%s,%s,%s,%s)",
                    (request_id, account_id, kind, "accepted", utcnow().isoformat()),
                )
        return request_id

    def export_user_data(self, account_id: str, products_by_sku: dict[str, Product]) -> dict[str, Any]:
        return {
            "beauty_id": self.get_beauty_id(account_id),
            "cart": cart_response_from_quantities(self.get_cart_quantities(account_id), products_by_sku),
            "histories": {
                "recommendations": self.list_history("recommendation_history", account_id),
                "scans": self.list_history("scan_history", account_id),
                "advisor": self.list_history("advisor_history", account_id),
            },
            "saved_routine": self.get_saved_routine(account_id),
            "advisor_messages": [message.model_dump() for message in self.list_advisor_messages(account_id)],
        }


def create_app_store() -> SQLiteAppStore | PostgresStore:
    if settings.database_url:
        return PostgresStore(settings.database_url)
    return SQLiteAppStore()
