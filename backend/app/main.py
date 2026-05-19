from __future__ import annotations

import logging
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from .advisor import build_advisor_response, clean_display_message, contains_internal_prompt_marker
from .auth_provider import get_auth_provider
from .catalog import get_product, load_catalog
from .checkout import get_checkout_provider
from .config import settings, validate_settings
from .provider_errors import ProviderUnavailable
from .recommendations import completion_for_beauty_id, recommend_products, tags_for_beauty_id
from .scan import UploadedPhoto, ScanValidationError, get_scan_provider, parse_beauty_id_json, validate_photo
from .schemas import (
    AddCartItemRequest,
    ActiveSelectionItemRequest,
    ActiveSelectionPatchRequest,
    ActiveSelectionPutRequest,
    ActiveSelectionResponse,
    ActiveSelectionItem,
    AdvisorHistoryResponse,
    AdvisorRequest,
    AdvisorResponse,
    AdvisorSelectionProduct,
    AuthLoginRequest,
    AuthRegisterRequest,
    AuthSessionResponse,
    BeautyID,
    BeautyIDResponse,
    CartResponse,
    CheckoutResponse,
    EnvironmentResponse,
    EventRequest,
    EventResponse,
    ExportResponse,
    FeedbackRequest,
    FeedbackResponse,
    LogoutRequest,
    PrivacyRequestResponse,
    Product,
    ProfileResponse,
    RecommendationsRequest,
    RecommendationsResponse,
    SavedRoutineRequest,
    SavedRoutineResponse,
    ScanResult,
    TokenRefreshRequest,
    UpdateCartItemRequest,
)
from .security import utcnow
from .store import StoredAccount, StoredSession, cart_response_from_quantities, create_app_store

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


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    detail = exc.detail if isinstance(exc.detail, str) else "request_failed"
    return error_response(request, exc.status_code, detail, human_error(detail))


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
                "details": {"errors": exc.errors()},
            }
        },
    )


def error_response(request: Request, status_code: int, code: str, message: str, details: dict[str, object] | None = None) -> JSONResponse:
    payload = {"error": {"code": code, "message": message, "request_id": getattr(request.state, "request_id", None)}}
    if details:
        payload["error"]["details"] = details
    return JSONResponse(status_code=status_code, content=payload)


def human_error(code: str) -> str:
    return {
        "account_exists": "An account with this email already exists.",
        "invalid_credentials": "Email or password is incorrect.",
        "not_authenticated": "A valid bearer token is required.",
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


def enforce_auth_rate_limit(request: Request, action: str) -> None:
    """Contract hook for production rate limiting.

    Keep this no-op in repository-local development; production deployments should
    wire IP/device/email throttling at the gateway or provider layer without
    logging passwords or raw identifiers.
    """
    logger.debug("auth_rate_limit_checked", extra={"request_id": getattr(request.state, "request_id", None), "action": action})


def make_auth_response(account: StoredAccount, session: StoredSession, provider: str) -> AuthSessionResponse:
    return AuthSessionResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_at=session.access_expires_at,
        refresh_expires_at=session.refresh_expires_at,
        account=account.public(),
        dev_mode=session.dev_mode,
        provider=provider,
    )


def bearer_token(authorization: Annotated[str | None, Header()] = None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="not_authenticated")
    return authorization.split(" ", 1)[1].strip()


def current_account(token: Annotated[str, Depends(bearer_token)]) -> StoredAccount:
    session = store.get_session_by_access(token)
    if not session:
        raise HTTPException(status_code=401, detail="token_expired")
    account = store.get_account(session.account_id)
    if not account:
        raise HTTPException(status_code=401, detail="not_authenticated")
    return account


def current_checkout_mode() -> str:
    return get_checkout_provider().mode()


def _products_by_sku() -> dict[str, Product]:
    return {item.sku: item for item in load_catalog(include_unavailable=True)}


def _saved_routine_response(account_id: str) -> SavedRoutineResponse:
    stored = store.get_saved_routine(account_id)
    if not stored:
        return SavedRoutineResponse(skus=[], products=[], updated_at=None)
    skus, updated_at = stored
    products = _products_by_sku()
    valid_skus = [sku for sku in skus if sku in products]
    return SavedRoutineResponse(skus=valid_skus, products=[products[sku] for sku in valid_skus], updated_at=updated_at)


def _validate_saved_routine_skus(skus: list[str], request: Request | None = None) -> list[str]:
    products = _products_by_sku()
    valid: list[str] = []
    invalid: list[str] = []
    for sku in skus:
        if sku in products:
            valid.append(sku)
        else:
            invalid.append(sku)
    if invalid:
        if request is not None:
            raise HTTPException(status_code=400, detail="invalid_saved_routine_sku")
        raise HTTPException(status_code=400, detail="invalid_saved_routine_sku")
    return valid


def _validate_selection_items(items: list[ActiveSelectionItemRequest]) -> list[dict[str, object]]:
    products = _products_by_sku()
    seen: set[str] = set()
    valid: list[dict[str, object]] = []
    now = utcnow()
    for item in items:
        if item.sku not in products:
            raise HTTPException(status_code=400, detail="invalid_active_selection_sku")
        if item.sku in seen:
            continue
        seen.add(item.sku)
        added_at = item.added_at or now
        valid.append(
            {
                "sku": item.sku,
                "source": item.source,
                "routine_step": item.routine_step,
                "reason": item.reason,
                "match_score": item.match_score,
                "added_at": added_at.isoformat(),
                "updated_at": (item.updated_at or now).isoformat(),
                "locked": item.locked,
                "metadata": item.metadata,
            }
        )
    return valid


def _selection_response(account_id: str, added_count: int = 0, already_in_selection_count: int = 0) -> ActiveSelectionResponse:
    stored = store.get_active_selection(account_id)
    if not stored:
        return ActiveSelectionResponse()
    raw_items, updated_at = stored
    products = _products_by_sku()
    items: list[ActiveSelectionItem] = []
    source_summary: dict[str, int] = {}
    match_scores: list[int] = []
    for raw in raw_items:
        sku = str(raw.get("sku", "")).strip().upper()
        product = products.get(sku)
        if not product:
            continue
        source = str(raw.get("source") or "manual")
        if source not in {"advisor", "recommendations", "manual", "cart", "saved_routine", "scan"}:
            source = "manual"
        source_summary[source] = source_summary.get(source, 0) + 1
        score = raw.get("match_score")
        if isinstance(score, int):
            match_scores.append(score)
        added_at_raw = raw.get("added_at")
        updated_at_raw = raw.get("updated_at")
        try:
            added_at = utcnow() if not added_at_raw else datetime.fromisoformat(str(added_at_raw))
        except ValueError:
            added_at = utcnow()
        parsed_updated_at = None
        if updated_at_raw:
            try:
                parsed_updated_at = datetime.fromisoformat(str(updated_at_raw))
            except ValueError:
                parsed_updated_at = None
        items.append(
            ActiveSelectionItem(
                sku=sku,
                product=product,
                source=source,  # type: ignore[arg-type]
                routine_step=raw.get("routine_step") if isinstance(raw.get("routine_step"), str) else None,
                reason=raw.get("reason") if isinstance(raw.get("reason"), str) else None,
                match_score=score if isinstance(score, int) else None,
                added_at=added_at,
                updated_at=parsed_updated_at,
                locked=bool(raw.get("locked")),
                metadata=raw.get("metadata") if isinstance(raw.get("metadata"), dict) else {},
            )
        )
    total = sum(item.product.price_value for item in items)
    average_match = round(sum(match_scores) / len(match_scores), 1) if match_scores else None
    return ActiveSelectionResponse(
        items=items,
        skus=[item.sku for item in items],
        count=len(items),
        total_price=total,
        average_match=average_match,
        updated_at=updated_at,
        source_summary=source_summary,
        added_count=added_count,
        already_in_selection_count=already_in_selection_count,
    )


def _merge_active_selection(account_id: str, incoming: list[ActiveSelectionItemRequest]) -> tuple[int, int]:
    valid_incoming = _validate_selection_items(incoming)
    stored = store.get_active_selection(account_id)
    existing = list(stored[0]) if stored else []
    by_sku = {str(item.get("sku", "")).strip().upper(): index for index, item in enumerate(existing)}
    added = 0
    duplicate = 0
    for item in valid_incoming:
        sku = str(item["sku"])
        if sku in by_sku:
            duplicate += 1
            old = dict(existing[by_sku[sku]])
            old.update({key: value for key, value in item.items() if key != "added_at" and value is not None})
            old["added_at"] = old.get("added_at") or item.get("added_at")
            old["updated_at"] = utcnow().isoformat()
            existing[by_sku[sku]] = old
        else:
            by_sku[sku] = len(existing)
            existing.append(item)
            added += 1
    store.save_active_selection(account_id, existing)
    return added, duplicate


def _advisor_selection_context(account_id: str, payload: AdvisorRequest) -> tuple[list[AdvisorSelectionProduct], list[str]]:
    try:
        products = _products_by_sku()
    except ProviderUnavailable:
        return payload.current_selection, payload.current_skus
    selection: list[AdvisorSelectionProduct] = []
    skus: list[str] = []

    def append_product(product: Product, routine_step: str | None = None) -> None:
        if product.sku in skus:
            return
        skus.append(product.sku)
        selection.append(
            AdvisorSelectionProduct(
                sku=product.sku,
                brand=product.brand,
                name=product.name,
                category=product.category,
                product_type=product.product_type,
                price_value=product.price_value,
                currency=product.currency,
                routine_step=routine_step,
            )
        )

    stored_selection = store.get_active_selection(account_id)
    if stored_selection:
        for item in stored_selection[0][:24]:
            product = products.get(str(item.get("sku", "")).strip().upper())
            if product:
                append_product(product, item.get("routine_step") if isinstance(item.get("routine_step"), str) else None)

    for item in payload.current_selection[:20]:
        product = products.get(item.sku)
        if product:
            append_product(product, item.routine_step)

    merged_skus = list(skus)
    for sku in [*payload.current_skus, *[item.sku for item in payload.current_cart]]:
        normalized = sku.strip().upper()
        if normalized and normalized not in merged_skus:
            merged_skus.append(normalized)
    return selection, merged_skus


@app.get("/health")
def health() -> dict[str, object]:
    errors = validate_settings()
    return {
        "status": "ok",
        "version": app.version,
        "settings": settings.public_mode(),
        "storage": store.stats(),
        "settings_errors": errors,
        "production_ready": not errors and settings.is_production,
    }


@app.get("/ready")
def ready() -> dict[str, object]:
    errors = validate_settings()
    catalog_count: int | None = None
    if not settings.is_production:
        catalog_count = len(load_catalog(include_unavailable=True))
    return {"status": "ready" if not errors else "not_ready", "catalog_items": catalog_count, "time": utcnow().isoformat(), "errors": errors}


@app.get("/v1/environment", response_model=EnvironmentResponse)
def environment() -> EnvironmentResponse:
    return EnvironmentResponse(app_env=settings.app_env, mode=settings.public_mode())


@app.post("/v1/auth/register", response_model=AuthSessionResponse)
def register(payload: AuthRegisterRequest, request: Request) -> AuthSessionResponse:
    enforce_auth_rate_limit(request, "register")
    provider = get_auth_provider()
    try:
        account = provider.register(store, payload.name, payload.email, payload.password)
    except ValueError:
        raise HTTPException(status_code=400, detail="account_exists") from None
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@app.post("/v1/auth/login", response_model=AuthSessionResponse)
def login(payload: AuthLoginRequest, request: Request) -> AuthSessionResponse:
    enforce_auth_rate_limit(request, "login")
    provider = get_auth_provider()
    account = provider.login(store, payload.email, payload.password)
    if not account:
        raise HTTPException(status_code=401, detail="invalid_credentials")
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@app.post("/v1/auth/dev-login", response_model=AuthSessionResponse)
def dev_login() -> AuthSessionResponse:
    if not (settings.allow_dev_auth and settings.is_non_production):
        raise HTTPException(status_code=403, detail="dev_auth_disabled")
    account = store.ensure_dev_account()
    session = store.create_session(account.account_id, dev_mode=True)
    return make_auth_response(account, session, "local_dev")


@app.post("/v1/auth/refresh", response_model=AuthSessionResponse)
def refresh(payload: TokenRefreshRequest) -> AuthSessionResponse:
    session = store.refresh_session(payload.refresh_token)
    if not session:
        raise HTTPException(status_code=401, detail="invalid_refresh_token")
    account = store.get_account(session.account_id)
    if not account:
        raise HTTPException(status_code=401, detail="not_authenticated")
    return make_auth_response(account, session, "refresh")


@app.post("/v1/auth/logout")
def logout(token: Annotated[str, Depends(bearer_token)], payload: LogoutRequest | None = None) -> dict[str, bool]:
    store.revoke_by_access(token)
    if payload and payload.refresh_token:
        store.revoke_by_refresh(payload.refresh_token)
    return {"ok": True}


@app.get("/v1/auth/me")
def me(account: Annotated[StoredAccount, Depends(current_account)]):
    return account.public()


@app.get("/v1/profile/me", response_model=ProfileResponse)
def profile(account: Annotated[StoredAccount, Depends(current_account)]) -> ProfileResponse:
    beauty_id = store.get_beauty_id(account.account_id)
    beauty_response = BeautyIDResponse(beauty_id=beauty_id, completion=completion_for_beauty_id(beauty_id), tags=tags_for_beauty_id(beauty_id)) if beauty_id else None
    saved_routine = _saved_routine_response(account.account_id)
    return ProfileResponse(
        account=account.public(),
        beauty_id=beauty_response,
        saved_routines=[saved_routine.model_dump(exclude_none=True)] if saved_routine.skus else [],
        recommendation_history=store.list_history("recommendation_history", account.account_id),
        order_history=[],
        privacy={
            "photo_storage": "Raw photos are not persisted by default. Configure a production storage/retention adapter before release.",
            "data_controls": ["export", "delete_request"],
            "medical_boundary": "The app is a cosmetic advisor, not a medical device.",
            "analytics": "No PII should be sent to analytics events.",
        },
    )


@app.get("/v1/beauty-id", response_model=BeautyIDResponse)
def get_beauty_id(account: Annotated[StoredAccount, Depends(current_account)]) -> BeautyIDResponse:
    beauty_id = store.get_beauty_id(account.account_id) or BeautyID(consent=False)
    return BeautyIDResponse(beauty_id=beauty_id, completion=completion_for_beauty_id(beauty_id), tags=tags_for_beauty_id(beauty_id))


@app.put("/v1/beauty-id", response_model=BeautyIDResponse)
def put_beauty_id(payload: BeautyID, account: Annotated[StoredAccount, Depends(current_account)]) -> BeautyIDResponse:
    if not payload.consent:
        raise HTTPException(status_code=400, detail="beauty_id_consent_required")
    saved = store.save_beauty_id(account.account_id, payload)
    return BeautyIDResponse(beauty_id=saved, completion=completion_for_beauty_id(saved), tags=tags_for_beauty_id(saved))


@app.get("/v1/catalog/products", response_model=list[Product])
def products(q: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
    return load_catalog(query=q, category=category, domain=domain, include_unavailable=include_unavailable)


@app.get("/v1/catalog/products/{sku}", response_model=Product)
def product_detail(sku: str) -> Product:
    product = get_product(sku)
    if not product:
        raise HTTPException(status_code=404, detail="product_not_found")
    return product


@app.post("/v1/recommendations", response_model=RecommendationsResponse)
def recommendations(payload: RecommendationsRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> RecommendationsResponse:
    beauty_id = payload.beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    response = recommend_products(payload.model_copy(update={"beauty_id": beauty_id}))
    known = {item.sku for item in load_catalog(include_unavailable=False)}
    response.products = [item for item in response.products if item.sku in known]
    response.routine = [item for item in response.routine if item.sku in known]
    response.hero = response.hero if response.hero and response.hero.sku in known else (response.products[0] if response.products else None)
    store.add_history("recommendation_history", account.account_id, {"focus": payload.focus, "hero_sku": response.hero.sku if response.hero else None, "count": len(response.products)})
    return response


@app.get("/v1/routines/current", response_model=SavedRoutineResponse)
def get_saved_routine(account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    return _saved_routine_response(account.account_id)


@app.put("/v1/routines/current", response_model=SavedRoutineResponse)
def put_saved_routine(payload: SavedRoutineRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    skus = _validate_saved_routine_skus(payload.skus)
    store.save_saved_routine(account.account_id, skus)
    return _saved_routine_response(account.account_id)


@app.delete("/v1/routines/current", response_model=SavedRoutineResponse)
def delete_saved_routine(account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    store.clear_saved_routine(account.account_id)
    return SavedRoutineResponse(skus=[], products=[], updated_at=None)


@app.get("/v1/selection/current", response_model=ActiveSelectionResponse)
def get_active_selection(account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    return _selection_response(account.account_id)


@app.put("/v1/selection/current", response_model=ActiveSelectionResponse)
def put_active_selection(payload: ActiveSelectionPutRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    items = _validate_selection_items(payload.items)
    store.save_active_selection(account.account_id, items)
    return _selection_response(account.account_id, added_count=len(items), already_in_selection_count=0)


@app.patch("/v1/selection/current/items", response_model=ActiveSelectionResponse)
def patch_active_selection(payload: ActiveSelectionPatchRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    added, duplicate = _merge_active_selection(account.account_id, payload.items)
    return _selection_response(account.account_id, added_count=added, already_in_selection_count=duplicate)


@app.delete("/v1/selection/current/items/{sku}", response_model=ActiveSelectionResponse)
def delete_active_selection_item(sku: str, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    normalized = sku.strip().upper()
    stored = store.get_active_selection(account.account_id)
    if not stored:
        return ActiveSelectionResponse()
    items, _ = stored
    remaining = [item for item in items if str(item.get("sku", "")).strip().upper() != normalized]
    store.save_active_selection(account.account_id, remaining)
    return _selection_response(account.account_id)


@app.delete("/v1/selection/current", response_model=ActiveSelectionResponse)
def clear_active_selection(account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    store.clear_active_selection(account.account_id)
    return ActiveSelectionResponse()


@app.post("/v1/photo/scan", response_model=ScanResult)
async def scan(
    account: Annotated[StoredAccount, Depends(current_account)],
    source: str = Form("questionnaire"),
    beauty_id_json: str | None = Form(None),
    photo: UploadFile | None = File(None),
) -> ScanResult:
    beauty_id = parse_beauty_id_json(beauty_id_json) if beauty_id_json else None
    beauty_id = beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    photo_bytes: bytes | None = None
    mime_type: str | None = None
    if photo is not None:
        photo_bytes = await photo.read()
        mime_type = photo.content_type
        validate_photo(photo_bytes, mime_type)
    result = await get_scan_provider().analyze(UploadedPhoto(photo_bytes, mime_type, source), beauty_id)
    store.add_history("scan_history", account.account_id, {"scan_id": result.scan_id, "source": source, "hero_sku": result.recommendations.hero.sku if result.recommendations.hero else None})
    return result


@app.delete("/v1/photo/scan/{scan_id}", response_model=PrivacyRequestResponse)
def delete_scan(scan_id: str, account: Annotated[StoredAccount, Depends(current_account)]) -> PrivacyRequestResponse:
    request_id = store.create_privacy_request(account.account_id, f"scan_delete:{scan_id}")
    return PrivacyRequestResponse(request_id=request_id, message="Scan deletion request accepted. Production storage adapter must delete any retained image derivatives.")


@app.post("/v1/advisor/message", response_model=AdvisorResponse)
async def advisor(payload: AdvisorRequest, request: Request, account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorResponse:
    beauty_id = payload.beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    clean_message = clean_display_message(payload.message)
    recent_history = store.list_advisor_messages(account.account_id, limit=24)
    current_selection, current_skus = _advisor_selection_context(account.account_id, payload)
    enriched_payload = payload.model_copy(
        update={
            "message": clean_message,
            "beauty_id": beauty_id,
            "conversation_history": recent_history,
            "current_selection": current_selection,
            "current_skus": current_skus,
        }
    )
    started = time.perf_counter()
    response = await build_advisor_response(enriched_payload)
    latency_ms = int((time.perf_counter() - started) * 1000)
    if contains_internal_prompt_marker(response.answer):
        logger.error("advisor_internal_prompt_leak_blocked", extra={"account_id": account.account_id, "prompt_version": response.prompt_version})
        raise HTTPException(status_code=502, detail="advisor_response_invalid")
    known = {item.sku for item in load_catalog(include_unavailable=False)}
    response.recommendations = [item for item in response.recommendations if item.sku in known]
    response.recommended_skus = [item.sku for item in response.recommendations]
    store.add_advisor_run(
        account.account_id,
        {
            "prompt_version": response.prompt_version,
            "provider": response.provider,
            "model": settings.openrouter_model if settings.advisor_provider in {"openrouter", "llm"} else None,
            "latency_ms": latency_ms,
            "fallback_reason": response.fallback_reason,
            "invalid_json": response.fallback_reason in {"advisor_provider_invalid_json", "advisor_provider_invalid_schema", "advisor_provider_invalid_response"},
            "unknown_sku_count": 1 if response.fallback_reason == "advisor_provider_ungrounded_skus" else 0,
            "medical_refusal": response.safety_note == "medical_boundary",
            "allowed_products_count": len(response.recommendations),
            "recommended_skus_count": len(response.recommended_skus),
            "action_count": len(response.actions),
            "request_id": getattr(request.state, "request_id", None),
        },
    )
    store.add_advisor_message(account.account_id, "user", clean_message, recommended_skus=[])
    store.add_advisor_message(
        account.account_id,
        "assistant",
        response.answer,
        recommended_skus=response.recommended_skus,
        provider=response.provider,
        prompt_version=response.prompt_version,
        safety_note=response.safety_note,
        fallback_reason=response.fallback_reason,
    )
    store.add_history(
        "advisor_history",
        account.account_id,
        {
            "message_length": len(clean_message),
            "recommendation_count": len(response.recommendations),
            "safety_note": response.safety_note,
            "provider": response.provider,
            "prompt_version": response.prompt_version,
            "fallback_reason": response.fallback_reason,
        },
    )
    return response


@app.get("/v1/advisor/history", response_model=AdvisorHistoryResponse)
def advisor_history(account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorHistoryResponse:
    return AdvisorHistoryResponse(messages=store.list_advisor_messages(account.account_id))


@app.delete("/v1/advisor/history", response_model=AdvisorHistoryResponse)
def clear_advisor_history(account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorHistoryResponse:
    store.clear_advisor_messages(account.account_id)
    return AdvisorHistoryResponse(messages=[])


@app.get("/v1/cart", response_model=CartResponse)
def get_cart(account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    return cart_response_from_quantities(store.get_cart_quantities(account.account_id), _products_by_sku(), current_checkout_mode())


@app.post("/v1/cart/items", response_model=CartResponse)
def add_cart_item(payload: AddCartItemRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    product = get_product(payload.sku)
    if not product:
        raise HTTPException(status_code=404, detail="product_not_found")
    if not product.availability or product.inventory_status == "out_of_stock":
        raise HTTPException(status_code=409, detail="product_unavailable")
    quantities = store.get_cart_quantities(account.account_id)
    quantities[product.sku] = min(50, quantities.get(product.sku, 0) + payload.quantity)
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, _products_by_sku(), current_checkout_mode())


@app.patch("/v1/cart/items/{sku}", response_model=CartResponse)
def update_cart_item(sku: str, payload: UpdateCartItemRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    quantities = store.get_cart_quantities(account.account_id)
    product = get_product(sku)
    normalized_sku = product.sku if product else sku
    if payload.quantity <= 0:
        quantities.pop(normalized_sku, None)
    else:
        if not product:
            raise HTTPException(status_code=404, detail="product_not_found")
        if not product.availability or product.inventory_status == "out_of_stock":
            raise HTTPException(status_code=409, detail="product_unavailable")
        quantities[normalized_sku] = payload.quantity
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, _products_by_sku(), current_checkout_mode())


@app.delete("/v1/cart/items/{sku}", response_model=CartResponse)
def remove_cart_item(sku: str, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    quantities = store.get_cart_quantities(account.account_id)
    product = get_product(sku)
    quantities.pop(product.sku if product else sku, None)
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, _products_by_sku(), current_checkout_mode())


@app.delete("/v1/cart", response_model=CartResponse)
def clear_cart(account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    store.save_cart(account.account_id, {})
    return cart_response_from_quantities({}, _products_by_sku(), current_checkout_mode())


@app.post("/v1/checkout/handoff", response_model=CheckoutResponse)
def checkout_handoff(account: Annotated[StoredAccount, Depends(current_account)]) -> CheckoutResponse:
    provider = get_checkout_provider()
    if provider.mode() == "unavailable" and settings.is_production:
        return provider.checkout(cart_response_from_quantities({}, {}, "unavailable"))
    cart = cart_response_from_quantities(store.get_cart_quantities(account.account_id), _products_by_sku(), provider.mode())
    if not cart.items:
        raise HTTPException(status_code=400, detail="cart_empty")
    return provider.checkout(cart)


@app.post("/v1/feedback", response_model=FeedbackResponse)
def feedback(payload: FeedbackRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> FeedbackResponse:
    feedback_id, created_at = store.add_feedback(
        account.account_id,
        payload.rating,
        payload.message,
        context=payload.context,
        app_version=payload.app_version,
        build=payload.build,
    )
    return FeedbackResponse(id=feedback_id, created_at=created_at)


@app.post("/v1/events", response_model=EventResponse)
def events(payload: EventRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> EventResponse:
    event_id, created_at = store.add_event(
        account.account_id,
        payload.event_name,
        payload=payload.payload,
        app_version=payload.app_version,
        build=payload.build,
        platform=payload.platform,
    )
    return EventResponse(id=event_id, created_at=created_at)


@app.post("/v1/privacy/export", response_model=ExportResponse)
def privacy_export(account: Annotated[StoredAccount, Depends(current_account)]) -> ExportResponse:
    data = store.export_user_data(account.account_id, _products_by_sku())
    return ExportResponse(account=account.public(), beauty_id=data["beauty_id"], cart=data["cart"], histories=data["histories"], exported_at=utcnow())


@app.post("/v1/privacy/delete-request", response_model=PrivacyRequestResponse)
def privacy_delete(account: Annotated[StoredAccount, Depends(current_account)]) -> PrivacyRequestResponse:
    request_id = store.create_privacy_request(account.account_id, "account_delete")
    return PrivacyRequestResponse(request_id=request_id, message="Account deletion request accepted. Connect the production identity/catalog/order data erasure workflow before App Store release.")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host=settings.api_host, port=settings.api_port, reload=settings.is_development)
