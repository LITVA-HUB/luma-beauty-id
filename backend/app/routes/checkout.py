from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..checkout import get_checkout_provider
from ..config import settings
from ..dependencies import current_account, get_store
from ..route_helpers import products_by_sku
from ..schemas import CheckoutResponse
from ..store import StoredAccount, cart_response_from_quantities

router = APIRouter()


@router.post("/v1/checkout/handoff", response_model=CheckoutResponse)
def checkout_handoff(account: Annotated[StoredAccount, Depends(current_account)]) -> CheckoutResponse:
    provider = get_checkout_provider()
    if provider.mode() == "unavailable" and settings.is_production:
        return provider.checkout(cart_response_from_quantities({}, {}, "unavailable"))
    cart = cart_response_from_quantities(get_store().get_cart_quantities(account.account_id), products_by_sku(), provider.mode())
    if not cart.items:
        raise HTTPException(status_code=400, detail="cart_empty")
    return provider.checkout(cart)
