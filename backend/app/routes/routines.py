from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..route_helpers import saved_routine_response, validate_saved_routine_skus
from ..schemas import SavedRoutineRequest, SavedRoutineResponse
from ..store import StoredAccount

router = APIRouter()


@router.get("/v1/routines/current", response_model=SavedRoutineResponse)
def get_saved_routine(account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    return saved_routine_response(account.account_id)


@router.put("/v1/routines/current", response_model=SavedRoutineResponse)
def put_saved_routine(payload: SavedRoutineRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    skus = validate_saved_routine_skus(payload.skus)
    get_store().save_saved_routine(account.account_id, skus)
    return saved_routine_response(account.account_id)


@router.delete("/v1/routines/current", response_model=SavedRoutineResponse)
def delete_saved_routine(account: Annotated[StoredAccount, Depends(current_account)]) -> SavedRoutineResponse:
    get_store().clear_saved_routine(account.account_id)
    return SavedRoutineResponse(skus=[], products=[], updated_at=None)
