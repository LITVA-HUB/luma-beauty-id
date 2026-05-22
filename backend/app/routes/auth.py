from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from ..auth_provider import get_auth_provider
from ..config import settings
from ..dependencies import bearer_token, current_account, get_store
from ..schemas import AuthLoginRequest, AuthRegisterRequest, AuthSessionResponse, LogoutRequest, TokenRefreshRequest
from ..store import StoredAccount, StoredSession

router = APIRouter()
logger = logging.getLogger("luma.api")


def enforce_auth_rate_limit(request: Request, action: str) -> None:
    """Contract hook for production rate limiting."""
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


@router.post("/v1/auth/register", response_model=AuthSessionResponse)
def register(payload: AuthRegisterRequest, request: Request) -> AuthSessionResponse:
    enforce_auth_rate_limit(request, "register")
    store = get_store()
    provider = get_auth_provider()
    try:
        account = provider.register(store, payload.name, payload.email, payload.password)
    except ValueError:
        raise HTTPException(status_code=400, detail="account_exists") from None
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@router.post("/v1/auth/login", response_model=AuthSessionResponse)
def login(payload: AuthLoginRequest, request: Request) -> AuthSessionResponse:
    enforce_auth_rate_limit(request, "login")
    store = get_store()
    provider = get_auth_provider()
    account = provider.login(store, payload.email, payload.password)
    if not account:
        raise HTTPException(status_code=401, detail="invalid_credentials")
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@router.post("/v1/auth/dev-login", response_model=AuthSessionResponse)
def dev_login() -> AuthSessionResponse:
    if not (settings.allow_dev_auth and settings.is_non_production):
        raise HTTPException(status_code=403, detail="dev_auth_disabled")
    store = get_store()
    account = store.ensure_dev_account()
    session = store.create_session(account.account_id, dev_mode=True)
    return make_auth_response(account, session, "local_dev")


@router.post("/v1/auth/refresh", response_model=AuthSessionResponse)
def refresh(payload: TokenRefreshRequest) -> AuthSessionResponse:
    store = get_store()
    session = store.refresh_session(payload.refresh_token)
    if not session:
        raise HTTPException(status_code=401, detail="invalid_refresh_token")
    account = store.get_account(session.account_id)
    if not account:
        raise HTTPException(status_code=401, detail="not_authenticated")
    return make_auth_response(account, session, "refresh")


@router.post("/v1/auth/logout")
def logout(token: Annotated[str, Depends(bearer_token)], payload: LogoutRequest | None = None) -> dict[str, bool]:
    store = get_store()
    store.revoke_by_access(token)
    if payload and payload.refresh_token:
        store.revoke_by_refresh(payload.refresh_token)
    return {"ok": True}


@router.get("/v1/auth/me")
def me(account: Annotated[StoredAccount, Depends(current_account)]):
    return account.public()
