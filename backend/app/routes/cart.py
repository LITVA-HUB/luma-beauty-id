from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from ..catalog import get_product
from ..dependencies import current_account, current_checkout_mode, get_store
from ..route_helpers import products_by_sku
from ..schemas import AddCartItemRequest, CartResponse, UpdateCartItemRequest
from ..store import StoredAccount, cart_response_from_quantities

router = APIRouter()


@router.get("/v1/cart", response_model=CartResponse)
def get_cart(account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    return cart_response_from_quantities(get_store().get_cart_quantities(account.account_id), products_by_sku(), current_checkout_mode())


@router.post("/v1/cart/items", response_model=CartResponse)
def add_cart_item(payload: AddCartItemRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    product = get_product(payload.sku)
    if not product:
        raise HTTPException(status_code=404, detail="product_not_found")
    if not product.availability or product.inventory_status == "out_of_stock":
        raise HTTPException(status_code=409, detail="product_unavailable")
    store = get_store()
    quantities = store.get_cart_quantities(account.account_id)
    quantities[product.sku] = min(50, quantities.get(product.sku, 0) + payload.quantity)
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, products_by_sku(), current_checkout_mode())


@router.patch("/v1/cart/items/{sku}", response_model=CartResponse)
def update_cart_item(sku: str, payload: UpdateCartItemRequest, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    store = get_store()
    quantities = store.get_cart_quantities(account.account_id)
    product = get_product(sku)
    normalized_sku = product.sku if product else sku
    if payload.quantity <= 0:
        quantities.pop(normalized_sku, None)
    else:
        if not product:
            raise HTTPException(status_code=404, detail="product_not_found")
        if not product.availability or product.inventory_status == "out_of_stock":
            raise HTTPException(status_code=409, detail="product_unavailable")
        quantities[normalized_sku] = payload.quantity
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, products_by_sku(), current_checkout_mode())


@router.delete("/v1/cart/items/{sku}", response_model=CartResponse)
def remove_cart_item(sku: str, account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    store = get_store()
    quantities = store.get_cart_quantities(account.account_id)
    product = get_product(sku)
    quantities.pop(product.sku if product else sku, None)
    store.save_cart(account.account_id, quantities)
    return cart_response_from_quantities(quantities, products_by_sku(), current_checkout_mode())


@router.delete("/v1/cart", response_model=CartResponse)
def clear_cart(account: Annotated[StoredAccount, Depends(current_account)]) -> CartResponse:
    get_store().save_cart(account.account_id, {})
    return cart_response_from_quantities({}, products_by_sku(), current_checkout_mode())
