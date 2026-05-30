from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from ..auth_provider import get_auth_provider
from ..config import settings
from ..dependencies import bearer_token, current_account, get_store
from ..provider_errors import ProviderUnavailable
from ..rate_limit import enforce as enforce_rate_limit
from ..schemas import (
    AuthLinkPhoneRequest,
    AuthLoginRequest,
    AuthRegisterRequest,
    AuthSessionResponse,
    LogoutRequest,
    TokenRefreshRequest,
)
from ..store import StoredAccount, StoredSession

router = APIRouter()
logger = logging.getLogger("luma.api")


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
    enforce_rate_limit(request, "register", phone=payload.phone)
    store = get_store()
    provider = get_auth_provider()
    try:
        account = provider.register(
            store, payload.name, email=payload.email, phone=payload.phone, password=payload.password
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc) or "account_exists") from None
    except ProviderUnavailable as exc:
        raise HTTPException(status_code=503, detail=exc.code) from None
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@router.post("/v1/auth/login", response_model=AuthSessionResponse)
def login(payload: AuthLoginRequest, request: Request) -> AuthSessionResponse:
    enforce_rate_limit(request, "login", phone=payload.phone)
    store = get_store()
    provider = get_auth_provider()
    try:
        account = provider.login(store, email=payload.email, phone=payload.phone, password=payload.password)
    except ProviderUnavailable as exc:
        raise HTTPException(status_code=503, detail=exc.code) from None
    if not account:
        raise HTTPException(status_code=401, detail="invalid_credentials")
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, provider.name)


@router.post("/v1/auth/guest", response_model=AuthSessionResponse)
def guest(request: Request) -> AuthSessionResponse:
    enforce_rate_limit(request, "guest")
    store = get_store()
    account = store.create_guest_account()
    session = store.create_session(account.account_id, dev_mode=False)
    return make_auth_response(account, session, "guest")


@router.post("/v1/auth/link-phone", response_model=AuthSessionResponse)
def link_phone(
    payload: AuthLinkPhoneRequest,
    account: Annotated[StoredAccount, Depends(current_account)],
    request: Request,
) -> AuthSessionResponse:
    enforce_rate_limit(request, "register", phone=payload.phone, account_id=account.account_id)
    store = get_store()
    try:
        upgraded = store.attach_phone(
            account.account_id, payload.phone, name=payload.name, password=payload.password
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc) or "phone_taken") from None
    if not upgraded:
        raise HTTPException(status_code=404, detail="not_authenticated")
    session = store.create_session(upgraded.account_id, dev_mode=False)
    return make_auth_response(upgraded, session, "local")


@router.post("/v1/auth/dev-login", response_model=AuthSessionResponse)
def dev_login(request: Request) -> AuthSessionResponse:
    if not (settings.allow_dev_auth and settings.is_non_production):
        raise HTTPException(status_code=403, detail="dev_auth_disabled")
    enforce_rate_limit(request, "dev_login")
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
