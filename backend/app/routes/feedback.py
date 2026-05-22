from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..schemas import FeedbackRequest, FeedbackResponse
from ..store import StoredAccount

router = APIRouter()


@router.post("/v1/feedback", response_model=FeedbackResponse)
def feedback(payload: FeedbackRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> FeedbackResponse:
    feedback_id, created_at = get_store().add_feedback(
        account.account_id,
        payload.rating,
        payload.message,
        context=payload.context,
        app_version=payload.app_version,
        build=payload.build,
    )
    return FeedbackResponse(id=feedback_id, created_at=created_at)
