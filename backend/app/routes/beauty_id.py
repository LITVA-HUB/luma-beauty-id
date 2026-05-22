from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..dependencies import current_account, get_store
from ..recommendations import completion_for_beauty_id, tags_for_beauty_id
from ..schemas import BeautyID, BeautyIDResponse
from ..store import StoredAccount

router = APIRouter()


@router.get("/v1/beauty-id", response_model=BeautyIDResponse)
def get_beauty_id(account: Annotated[StoredAccount, Depends(current_account)]) -> BeautyIDResponse:
    beauty_id = get_store().get_beauty_id(account.account_id) or BeautyID(consent=False)
    return BeautyIDResponse(beauty_id=beauty_id, completion=completion_for_beauty_id(beauty_id), tags=tags_for_beauty_id(beauty_id))


@router.put("/v1/beauty-id", response_model=BeautyIDResponse)
def put_beauty_id(payload: BeautyID, account: Annotated[StoredAccount, Depends(current_account)]) -> BeautyIDResponse:
    if not payload.consent:
        raise HTTPException(status_code=400, detail="beauty_id_consent_required")
    saved = get_store().save_beauty_id(account.account_id, payload)
    return BeautyIDResponse(beauty_id=saved, completion=completion_for_beauty_id(saved), tags=tags_for_beauty_id(saved))
