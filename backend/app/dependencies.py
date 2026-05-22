from __future__ import annotations

from typing import Annotated, Any

from fastapi import Depends, Header, HTTPException

from .checkout import get_checkout_provider
from .store import StoredAccount


def get_store() -> Any:
    from . import main as main_module

    return main_module.store


def bearer_token(authorization: Annotated[str | None, Header()] = None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="not_authenticated")
    return authorization.split(" ", 1)[1].strip()


def current_account(token: Annotated[str, Depends(bearer_token)]) -> StoredAccount:
    store = get_store()
    session = store.get_session_by_access(token)
    if not session:
        raise HTTPException(status_code=401, detail="token_expired")
    account = store.get_account(session.account_id)
    if not account:
        raise HTTPException(status_code=401, detail="not_authenticated")
    return account


def current_checkout_mode() -> str:
    return get_checkout_provider().mode()
