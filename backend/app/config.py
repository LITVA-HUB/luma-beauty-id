from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


def _load_local_env_file() -> None:
    """Load backend/.env for local execution without overriding real environment.

    Deployment platforms and secret managers should still inject environment
    variables directly. This tiny loader exists so `python3 -m app.main` and
    local smoke scripts behave the same way as the README commands. It never
    prints or logs values.
    """
    candidates = [Path.cwd() / ".env", Path(__file__).resolve().parents[1] / ".env"]
    for candidate in candidates:
        if not candidate.exists() or not candidate.is_file():
            continue
        for raw_line in candidate.read_text(errors="ignore").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
        break


_load_local_env_file()

EnvironmentMode = Literal["development", "staging", "production"]


def _bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _csv(name: str, default: str = "") -> tuple[str, ...]:
    raw = os.getenv(name, default)
    return tuple(item.strip() for item in raw.split(",") if item.strip())


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _str(name: str, default: str = "") -> str:
    value = os.getenv(name)
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


@dataclass
class Settings:
    app_env: str = _str("APP_ENV", _str("APP_ENVIRONMENT", "development")).lower()
    api_host: str = _str("API_HOST", "127.0.0.1")
    api_port: int = _int("API_PORT", 8010)
    public_api_base_url: str = _str("PUBLIC_API_BASE_URL", _str("API_PUBLIC_BASE_URL", "http://127.0.0.1:8010"))
    database_url: str = _str("DATABASE_URL", "")
    store_path: str = _str("STORE_PATH", ".data/luma_beauty.sqlite3")
    cors_allow_origins: tuple[str, ...] = _csv("CORS_ALLOW_ORIGINS", "http://127.0.0.1:3000,http://localhost:3000")

    allow_dev_auth: bool = _bool("ALLOW_DEV_AUTH", True)
    auth_provider: str = _str("AUTH_PROVIDER", "local").lower()
    auth_provider_url: str = _str("AUTH_PROVIDER_URL", "")
    auth_provider_api_key: str = _str("AUTH_PROVIDER_API_KEY", "")
    access_token_ttl_minutes: int = _int("ACCESS_TOKEN_TTL_MINUTES", 30)
    refresh_token_ttl_days: int = _int("REFRESH_TOKEN_TTL_DAYS", 30)

    catalog_provider: str = _str("CATALOG_PROVIDER", "local").lower()
    catalog_api_base_url: str = _str("CATALOG_API_BASE_URL", "")
    catalog_api_token: str = _str("CATALOG_API_TOKEN", "")

    checkout_provider: str = _str("CHECKOUT_PROVIDER", "development_handoff").lower()
    checkout_handoff_url: str = _str("CHECKOUT_HANDOFF_URL", "")
    checkout_api_key: str = _str("CHECKOUT_API_KEY", "")

    scan_provider: str = _str("SCAN_PROVIDER", "dev").lower()
    scan_provider_url: str = _str("SCAN_PROVIDER_URL", "")
    scan_provider_api_key: str = _str("SCAN_PROVIDER_API_KEY", "")
    max_photo_bytes: int = _int("MAX_PHOTO_BYTES", 5_000_000)
    allowed_photo_mime_types: tuple[str, ...] = _csv("ALLOWED_PHOTO_MIME_TYPES", "image/jpeg,image/png,image/heic,image/heif")

    advisor_provider: str = _str("ADVISOR_PROVIDER", "deterministic").lower()
    advisor_prompt_version: str = _str("ADVISOR_PROMPT_VERSION", "luma-advisor-2026-05-rc2")
    advisor_timeout_seconds: int = _int("ADVISOR_TIMEOUT_SECONDS", 18)
    openrouter_api_key: str = _str("OPENROUTER_API_KEY", "")
    openrouter_base_url: str = _str("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1").rstrip("/")
    openrouter_model: str = _str("OPENROUTER_MODEL", "")
    openrouter_timeout_seconds: int = _int("OPENROUTER_TIMEOUT_SECONDS", 30)
    openrouter_max_retries: int = _int("OPENROUTER_MAX_RETRIES", 2)
    openrouter_response_format: str = _str("OPENROUTER_RESPONSE_FORMAT", "json_schema").lower()
    gemini_api_key: str = _str("GEMINI_API_KEY", "")

    log_level: str = _str("LOG_LEVEL", "INFO")

    rate_limit_enabled: bool = _bool("RATE_LIMIT_ENABLED", True)

    # When true (and DATABASE_URL points at Postgres), the app runs
    # `alembic upgrade head` on startup. Off by default so local SQLite runs and
    # the test suite never touch Alembic; turn it on for managed Postgres deploys.
    run_db_migrations: bool = _bool("RUN_DB_MIGRATIONS", False)

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def is_staging(self) -> bool:
        return self.app_env == "staging"

    @property
    def is_development(self) -> bool:
        return self.app_env == "development"

    @property
    def is_non_production(self) -> bool:
        return not self.is_production

    def public_mode(self) -> dict[str, object]:
        return {
            "app_env": self.app_env,
            "auth_provider": self.auth_provider,
            "catalog_provider": self.catalog_provider,
            "checkout_provider": self.checkout_provider,
            "scan_provider": self.scan_provider,
            "advisor_provider": self.advisor_provider,
            "advisor_prompt_version": self.advisor_prompt_version,
            "openrouter_configured": bool(self.openrouter_api_key),
            "openrouter_response_format": self.openrouter_response_format,
            "dev_auth_enabled": self.allow_dev_auth and self.is_non_production,
        }


settings = Settings()


def validate_settings() -> list[str]:
    errors: list[str] = []
    if settings.app_env not in {"development", "staging", "production"}:
        errors.append("APP_ENV must be development, staging or production")
    if settings.is_production:
        if settings.allow_dev_auth:
            errors.append("ALLOW_DEV_AUTH must be false in production")
        if settings.auth_provider == "local":
            errors.append("AUTH_PROVIDER=local is not allowed in production")
        if settings.auth_provider == "external" and not (settings.auth_provider_url and settings.auth_provider_api_key):
            errors.append("AUTH_PROVIDER_URL and AUTH_PROVIDER_API_KEY are required for production external auth")
        if settings.auth_provider == "external" and settings.auth_provider_url and settings.auth_provider_api_key:
            errors.append("Production auth adapter contract is not implemented in this repository")
        if settings.catalog_provider == "local":
            errors.append("CATALOG_PROVIDER=local is not allowed in production")
        if settings.catalog_provider == "external" and not (settings.catalog_api_base_url and settings.catalog_api_token):
            errors.append("CATALOG_API_BASE_URL and CATALOG_API_TOKEN are required for production catalog")
        if settings.catalog_provider == "external" and settings.catalog_api_base_url and settings.catalog_api_token:
            errors.append("Production catalog adapter contract is not implemented in this repository")
        if settings.checkout_provider in {"development_handoff", "local"}:
            errors.append("development checkout handoff is not allowed in production")
        if settings.checkout_provider == "external" and not (settings.checkout_handoff_url and settings.checkout_api_key):
            errors.append("CHECKOUT_HANDOFF_URL and CHECKOUT_API_KEY are required for production checkout")
        if settings.checkout_provider == "external" and settings.checkout_handoff_url and settings.checkout_api_key:
            errors.append("Production checkout adapter contract is not implemented in this repository")
        if settings.scan_provider == "dev":
            errors.append("SCAN_PROVIDER=dev is not allowed in production")
        if settings.scan_provider == "external" and not (settings.scan_provider_url and settings.scan_provider_api_key):
            errors.append("SCAN_PROVIDER_URL and SCAN_PROVIDER_API_KEY are required for production scan")
        if settings.scan_provider == "external" and settings.scan_provider_url and settings.scan_provider_api_key:
            errors.append("Production scan adapter contract is not implemented in this repository")
        if settings.advisor_provider == "deterministic":
            errors.append("ADVISOR_PROVIDER=deterministic is not allowed as the primary production provider")
        if settings.advisor_provider in {"openrouter", "llm"}:
            if not settings.openrouter_api_key:
                errors.append("OPENROUTER_API_KEY is required for production LLM advisor")
            if not settings.openrouter_model:
                errors.append("OPENROUTER_MODEL is required for production LLM advisor")
            if not settings.openrouter_base_url.startswith("https://"):
                errors.append("OPENROUTER_BASE_URL must use https in production")
        if settings.advisor_provider == "gemini" and not settings.gemini_api_key:
            errors.append("GEMINI_API_KEY is required for production Gemini advisor")
        if not settings.database_url and (not settings.store_path or settings.store_path.startswith(":memory:")):
            errors.append("DATABASE_URL or persistent STORE_PATH is required in production")
    return errors
