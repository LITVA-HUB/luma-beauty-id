from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile

from ..dependencies import current_account, get_store
from ..rate_limit import enforce as enforce_rate_limit
from ..scan import UploadedPhoto, get_scan_provider, parse_beauty_id_json, validate_photo
from ..schemas import BeautyID, PrivacyRequestResponse, ScanResult
from ..store import StoredAccount

router = APIRouter()


@router.post("/v1/photo/scan", response_model=ScanResult)
async def scan(
    request: Request,
    account: Annotated[StoredAccount, Depends(current_account)],
    source: str = Form("questionnaire"),
    beauty_id_json: str | None = Form(None),
    photo: UploadFile | None = File(None),
) -> ScanResult:
    enforce_rate_limit(request, "scan", account_id=account.account_id)
    store = get_store()
    beauty_id = parse_beauty_id_json(beauty_id_json) if beauty_id_json else None
    beauty_id = beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    photo_bytes: bytes | None = None
    mime_type: str | None = None
    if photo is not None:
        photo_bytes = await photo.read()
        mime_type = photo.content_type
        validate_photo(photo_bytes, mime_type)
    result = await get_scan_provider().analyze(UploadedPhoto(photo_bytes, mime_type, source), beauty_id)
    store.add_history("scan_history", account.account_id, {"scan_id": result.scan_id, "source": source, "hero_sku": result.recommendations.hero.sku if result.recommendations.hero else None})
    return result


@router.delete("/v1/photo/scan/{scan_id}", response_model=PrivacyRequestResponse)
def delete_scan(scan_id: str, account: Annotated[StoredAccount, Depends(current_account)]) -> PrivacyRequestResponse:
    request_id = get_store().create_privacy_request(account.account_id, f"scan_delete:{scan_id}")
    return PrivacyRequestResponse(request_id=request_id, message="Scan deletion request accepted. Production storage adapter must delete any retained image derivatives.")
