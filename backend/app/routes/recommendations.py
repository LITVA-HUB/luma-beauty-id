from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..catalog import load_catalog
from ..dependencies import current_account, get_store
from ..recommendations import recommend_products
from ..schemas import BeautyID, RecommendationsRequest, RecommendationsResponse
from ..store import StoredAccount

router = APIRouter()


def _grounded_recommendations(payload: RecommendationsRequest, beauty_id: BeautyID) -> RecommendationsResponse:
    response = recommend_products(payload.model_copy(update={"beauty_id": beauty_id}))
    known = {item.sku for item in load_catalog(include_unavailable=False)}
    response.products = [item for item in response.products if item.sku in known]
    response.routine = [item for item in response.routine if item.sku in known]
    response.hero = response.hero if response.hero and response.hero.sku in known else (response.products[0] if response.products else None)
    return response


@router.post("/v1/recommendations", response_model=RecommendationsResponse)
def recommendations(payload: RecommendationsRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> RecommendationsResponse:
    store = get_store()
    beauty_id = payload.beauty_id or store.get_beauty_id(account.account_id) or BeautyID(consent=True)
    response = _grounded_recommendations(payload, beauty_id)
    store.add_history("recommendation_history", account.account_id, {"focus": payload.focus, "hero_sku": response.hero.sku if response.hero else None, "count": len(response.products)})
    return response


@router.post("/v1/recommendations/preview", response_model=RecommendationsResponse)
def recommendations_preview(payload: RecommendationsRequest) -> RecommendationsResponse:
    """Public, unauthenticated preview for the onboarding flow before sign-up.

    Runs the same deterministic, catalog-grounded recommender as the authenticated
    endpoint, but requires no account and stores no history. This lets a guest see
    the same real catalog they will get after registration.
    """
    beauty_id = payload.beauty_id or BeautyID(consent=True)
    return _grounded_recommendations(payload, beauty_id)
