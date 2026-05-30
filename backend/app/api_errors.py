from __future__ import annotations

import logging

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .provider_errors import ProviderUnavailable
from .scan import ScanValidationError


def error_response(request: Request, status_code: int, code: str, message: str, details: dict[str, object] | None = None, headers: dict[str, str] | None = None) -> JSONResponse:
    payload = {"error": {"code": code, "message": message, "request_id": getattr(request.state, "request_id", None)}}
    if details:
        payload["error"]["details"] = details
    return JSONResponse(status_code=status_code, content=payload, headers=headers)


def human_error(code: str) -> str:
    return {
        "account_exists": "An account with this email already exists.",
        "invalid_credentials": "Email or password is incorrect.",
        "not_authenticated": "A valid bearer token is required.",
        "rate_limited": "Too many requests. Please slow down and try again shortly.",
        "token_expired": "Session expired. Please sign in again.",
        "invalid_refresh_token": "Refresh token is invalid or expired.",
        "dev_auth_disabled": "Development auth is disabled in this environment.",
        "product_not_found": "Product was not found in the catalog.",
        "product_unavailable": "Product is currently unavailable.",
        "cart_empty": "Cart is empty.",
        "beauty_id_consent_required": "Consent is required before saving Beauty ID.",
        "invalid_saved_routine_sku": "Saved routine can include only current LUMA catalog products.",
        "invalid_active_selection_sku": "Active selection can include only current LUMA catalog products.",
    }.get(code, code.replace("_", " ").capitalize())


def register_exception_handlers(app: FastAPI, logger: logging.Logger) -> None:
    @app.exception_handler(HTTPException)
    async def http_exception_handler(request: Request, exc: HTTPException):
        detail = exc.detail if isinstance(exc.detail, str) else "request_failed"
        return error_response(request, exc.status_code, detail, human_error(detail), headers=exc.headers)

    @app.exception_handler(ProviderUnavailable)
    async def provider_exception_handler(request: Request, exc: ProviderUnavailable):
        logger.warning("provider_unavailable", extra={"request_id": getattr(request.state, "request_id", None), "code": exc.code})
        return error_response(request, exc.status_code, exc.code, exc.message)

    @app.exception_handler(ScanValidationError)
    async def scan_validation_exception_handler(request: Request, exc: ScanValidationError):
        status_code = 413 if exc.code == "photo_too_large" else 415
        return error_response(request, status_code, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(request: Request, exc: RequestValidationError):
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": {
                    "code": "validation_error",
                    "message": "Request validation failed.",
                    "request_id": getattr(request.state, "request_id", None),
                    "details": {"errors": jsonable_encoder(exc.errors())},
                }
            },
        )
