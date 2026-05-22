from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..schemas import EventRequest, EventResponse
from ..store import StoredAccount

router = APIRouter()


@router.post("/v1/events", response_model=EventResponse)
def events(payload: EventRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> EventResponse:
    event_id, created_at = get_store().add_event(
        account.account_id,
        payload.event_name,
        payload=payload.payload,
        app_version=payload.app_version,
        build=payload.build,
        platform=payload.platform,
    )
    return EventResponse(id=event_id, created_at=created_at)
