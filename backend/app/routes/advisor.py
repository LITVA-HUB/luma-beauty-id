from __future__ import annotations

import logging
import time
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request

from ..advisor import build_advisor_response, clean_display_message, contains_internal_prompt_marker
from ..catalog import load_catalog
from ..config import settings
from ..dependencies import current_account, get_store
from ..route_helpers import advisor_selection_context
from ..schemas import AdvisorHistoryResponse, AdvisorRequest, AdvisorResponse, BeautyID
from ..store import StoredAccount

router = APIRouter()
logger = logging.getLogger("luma.api")


@router.post("/v1/advisor/message", response_model=AdvisorResponse)
async def advisor(payload: AdvisorRequest, request: Request, account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorResponse:
    store = get_store()
    beauty_id = payload.beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    clean_message = clean_display_message(payload.message)
    recent_history = store.list_advisor_messages(account.account_id, limit=24)
    current_selection, current_skus = advisor_selection_context(account.account_id, payload)
    enriched_payload = payload.model_copy(
        update={
            "message": clean_message,
            "beauty_id": beauty_id,
            "conversation_history": recent_history,
            "current_selection": current_selection,
            "current_skus": current_skus,
        }
    )
    started = time.perf_counter()
    response = await build_advisor_response(enriched_payload)
    latency_ms = int((time.perf_counter() - started) * 1000)
    if contains_internal_prompt_marker(response.answer):
        logger.error("advisor_internal_prompt_leak_blocked", extra={"account_id": account.account_id, "prompt_version": response.prompt_version})
        raise HTTPException(status_code=502, detail="advisor_response_invalid")
    known = {item.sku for item in load_catalog(include_unavailable=False)}
    response.recommendations = [item for item in response.recommendations if item.sku in known]
    response.recommended_skus = [item.sku for item in response.recommendations]
    store.add_advisor_run(
        account.account_id,
        {
            "prompt_version": response.prompt_version,
            "provider": response.provider,
            "model": settings.openrouter_model if settings.advisor_provider in {"openrouter", "llm"} else None,
            "latency_ms": latency_ms,
            "fallback_reason": response.fallback_reason,
            "invalid_json": response.fallback_reason in {"advisor_provider_invalid_json", "advisor_provider_invalid_schema", "advisor_provider_invalid_response"},
            "unknown_sku_count": 1 if response.fallback_reason == "advisor_provider_ungrounded_skus" else 0,
            "medical_refusal": response.safety_note == "medical_boundary",
            "allowed_products_count": len(response.recommendations),
            "recommended_skus_count": len(response.recommended_skus),
            "action_count": len(response.actions),
            "request_id": getattr(request.state, "request_id", None),
        },
    )
    store.add_advisor_message(account.account_id, "user", clean_message, recommended_skus=[])
    store.add_advisor_message(
        account.account_id,
        "assistant",
        response.answer,
        recommended_skus=response.recommended_skus,
        provider=response.provider,
        prompt_version=response.prompt_version,
        safety_note=response.safety_note,
        fallback_reason=response.fallback_reason,
    )
    store.add_history(
        "advisor_history",
        account.account_id,
        {
            "message_length": len(clean_message),
            "recommendation_count": len(response.recommendations),
            "safety_note": response.safety_note,
            "provider": response.provider,
            "prompt_version": response.prompt_version,
            "fallback_reason": response.fallback_reason,
        },
    )
    return response


@router.get("/v1/advisor/history", response_model=AdvisorHistoryResponse)
def advisor_history(account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorHistoryResponse:
    return AdvisorHistoryResponse(messages=get_store().list_advisor_messages(account.account_id))


@router.delete("/v1/advisor/history", response_model=AdvisorHistoryResponse)
def clear_advisor_history(account: Annotated[StoredAccount, Depends(current_account)]) -> AdvisorHistoryResponse:
    get_store().clear_advisor_messages(account.account_id)
    return AdvisorHistoryResponse(messages=[])
