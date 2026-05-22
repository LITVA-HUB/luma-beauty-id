from __future__ import annotations

from fastapi import APIRouter, HTTPException

from ..catalog import get_product, load_catalog
from ..schemas import Product

router = APIRouter()


@router.get("/v1/catalog/products", response_model=list[Product])
def products(q: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
    return load_catalog(query=q, category=category, domain=domain, include_unavailable=include_unavailable)


@router.get("/v1/catalog/products/{sku}", response_model=Product)
def product_detail(sku: str) -> Product:
    product = get_product(sku)
    if not product:
        raise HTTPException(status_code=404, detail="product_not_found")
    return product
