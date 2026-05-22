from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..route_helpers import merge_active_selection, selection_response, validate_selection_items
from ..schemas import ActiveSelectionPatchRequest, ActiveSelectionPutRequest, ActiveSelectionResponse
from ..store import StoredAccount

router = APIRouter()


@router.get("/v1/selection/current", response_model=ActiveSelectionResponse)
def get_active_selection(account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    return selection_response(account.account_id)


@router.put("/v1/selection/current", response_model=ActiveSelectionResponse)
def put_active_selection(payload: ActiveSelectionPutRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    items = validate_selection_items(payload.items)
    get_store().save_active_selection(account.account_id, items)
    return selection_response(account.account_id, added_count=len(items), already_in_selection_count=0)


@router.patch("/v1/selection/current/items", response_model=ActiveSelectionResponse)
def patch_active_selection(payload: ActiveSelectionPatchRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    added, duplicate = merge_active_selection(account.account_id, payload.items)
    return selection_response(account.account_id, added_count=added, already_in_selection_count=duplicate)


@router.delete("/v1/selection/current/items/{sku}", response_model=ActiveSelectionResponse)
def delete_active_selection_item(sku: str, account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    normalized = sku.strip().upper()
    store = get_store()
    stored = store.get_active_selection(account.account_id)
    if not stored:
        return ActiveSelectionResponse()
    items, _ = stored
    remaining = [item for item in items if str(item.get("sku", "")).strip().upper() != normalized]
    store.save_active_selection(account.account_id, remaining)
    return selection_response(account.account_id)


@router.delete("/v1/selection/current", response_model=ActiveSelectionResponse)
def clear_active_selection(account: Annotated[StoredAccount, Depends(current_account)]) -> ActiveSelectionResponse:
    get_store().clear_active_selection(account.account_id)
    return ActiveSelectionResponse()
