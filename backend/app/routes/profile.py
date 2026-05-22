from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..recommendations import completion_for_beauty_id, tags_for_beauty_id
from ..route_helpers import saved_routine_response
from ..schemas import BeautyIDResponse, ProfileResponse
from ..store import StoredAccount

router = APIRouter()


@router.get("/v1/profile/me", response_model=ProfileResponse)
def profile(account: Annotated[StoredAccount, Depends(current_account)]) -> ProfileResponse:
    store = get_store()
    beauty_id = store.get_beauty_id(account.account_id)
    beauty_response = BeautyIDResponse(beauty_id=beauty_id, completion=completion_for_beauty_id(beauty_id), tags=tags_for_beauty_id(beauty_id)) if beauty_id else None
    saved_routine = saved_routine_response(account.account_id)
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
