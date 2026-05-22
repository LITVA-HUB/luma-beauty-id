from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..dependencies import current_account, get_store
from ..route_helpers import products_by_sku
from ..schemas import ExportResponse, PrivacyRequestResponse
from ..security import utcnow
from ..store import StoredAccount

router = APIRouter()


@router.post("/v1/privacy/export", response_model=ExportResponse)
def privacy_export(account: Annotated[StoredAccount, Depends(current_account)]) -> ExportResponse:
    data = get_store().export_user_data(account.account_id, products_by_sku())
    return ExportResponse(account=account.public(), beauty_id=data["beauty_id"], cart=data["cart"], histories=data["histories"], exported_at=utcnow())


@router.post("/v1/privacy/delete-request", response_model=PrivacyRequestResponse)
def privacy_delete(account: Annotated[StoredAccount, Depends(current_account)]) -> PrivacyRequestResponse:
    request_id = get_store().create_privacy_request(account.account_id, "account_delete")
    return PrivacyRequestResponse(request_id=request_id, message="Account deletion request accepted. Connect the production identity/catalog/order data erasure workflow before App Store release.")
