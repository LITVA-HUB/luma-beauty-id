from __future__ import annotations

from fastapi import APIRouter, Request

from ..catalog import load_catalog
from ..config import settings, validate_settings
from ..dependencies import get_store
from ..schemas import EnvironmentResponse
from ..security import utcnow

router = APIRouter()


@router.get("/health")
def health(request: Request) -> dict[str, object]:
    errors = validate_settings()
    return {
        "status": "ok",
        "version": request.app.version,
        "settings": settings.public_mode(),
        "storage": get_store().stats(),
        "settings_errors": errors,
        "production_ready": not errors and settings.is_production,
    }


@router.get("/ready")
def ready() -> dict[str, object]:
    errors = validate_settings()
    catalog_count: int | None = None
    if not settings.is_production:
        catalog_count = len(load_catalog(include_unavailable=True))
    return {"status": "ready" if not errors else "not_ready", "catalog_items": catalog_count, "time": utcnow().isoformat(), "errors": errors}


@router.get("/v1/environment", response_model=EnvironmentResponse)
def environment() -> EnvironmentResponse:
    return EnvironmentResponse(app_env=settings.app_env, mode=settings.public_mode())
