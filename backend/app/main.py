from __future__ import annotations

import logging
import uuid
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .api_errors import register_exception_handlers
from .config import settings
from .routes import ROUTERS
from .storage.factory import create_app_store
from .storage.migrations import run_migrations_if_enabled

logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO), format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("luma.api")

app = FastAPI(
    title="Luma Beauty ID API",
    version="1.2.0-rc2",
    description="Release-candidate API foundation for a non-medical premium beauty concierge iPhone app.",
)

STATIC_ASSETS_DIR = Path(__file__).resolve().parent / "static" / "assets"
app.mount("/assets", StaticFiles(directory=str(STATIC_ASSETS_DIR)), name="assets")

if settings.cors_allow_origins and settings.is_non_production:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_allow_origins),
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    )

run_migrations_if_enabled()
store = create_app_store()


@app.middleware("http")
async def request_context_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID") or str(uuid.uuid4())
    request.state.request_id = request_id
    content_length = request.headers.get("content-length")
    if content_length and request.url.path.startswith("/v1/photo/"):
        try:
            if int(content_length) > settings.max_photo_bytes + 32_768:
                return JSONResponse(
                    status_code=413,
                    content={"error": {"code": "request_body_too_large", "message": "Photo upload is larger than the configured limit.", "request_id": request_id}},
                )
        except ValueError:
            pass
    try:
        response = await call_next(request)
    except Exception:
        logger.exception("unhandled_request_error", extra={"request_id": request_id, "path": request.url.path})
        raise
    response.headers["X-Request-ID"] = request_id
    return response


register_exception_handlers(app, logger)

for router in ROUTERS:
    app.include_router(router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host=settings.api_host, port=settings.api_port, reload=settings.is_development)
