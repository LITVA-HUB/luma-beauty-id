from __future__ import annotations

import json
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path

from .config import settings
from .provider_errors import ProviderUnavailable
from .schemas import Product

CATALOG_PATH = Path(__file__).parent / "data" / "catalog.json"
UTC = timezone.utc

CATEGORY_LABELS = {
    "cleanser": "очищение",
    "toner": "тонер",
    "serum": "сыворотка",
    "moisturizer": "крем",
    "spf": "SPF",
    "primer": "праймер",
    "foundation": "тон",
    "skin_tint": "skin tint",
    "concealer": "консилер",
    "powder": "пудра",
    "eyeshadow_palette": "палетка теней",
    "blush": "румяна",
    "brow_gel": "гель для бровей",
    "mascara": "тушь",
    "highlighter": "сияние",
    "lip_balm": "бальзам",
    "lip_tint": "тинт",
    "lipstick": "помада",
    "setting_spray": "фиксация",
    "mask": "маска",
}


class CatalogProvider(ABC):
    name: str

    @abstractmethod
    def list_products(self, query: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
        raise NotImplementedError

    def get_product(self, sku: str) -> Product | None:
        normalized = sku.strip().lower()
        for item in self.list_products(include_unavailable=True):
            if item.sku.lower() == normalized:
                return item
        return None


class LocalCatalogProvider(CatalogProvider):
    name = "local_seed"

    @lru_cache(maxsize=1)
    def _load_seed(self) -> tuple[Product, ...]:
        data = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        products: list[Product] = []
        now = datetime(2026, 5, 6, tzinfo=UTC)
        for index, raw in enumerate(data):
            item = dict(raw)
            item.setdefault("source", "synthetic_catalog")
            item.setdefault("currency", "RUB")
            item.setdefault("gallery", [])
            item.setdefault("warnings", list(item.get("exclusions") or []))
            item.setdefault("updated_at", now.isoformat())
            # Keep one explicit unavailable SKU in the seed so mobile and API states can be tested.
            if index == len(data) - 1:
                item["availability"] = False
                item["inventory_status"] = "out_of_stock"
                item["warnings"] = [*item.get("warnings", []), "currently unavailable in the synthetic catalog"]
            else:
                item.setdefault("inventory_status", "in_stock" if item.get("availability", True) else "out_of_stock")
            products.append(Product.parse_obj(item))
        return tuple(products)

    def list_products(self, query: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
        items = list(self._load_seed())
        if query:
            needle = query.strip().lower()
            items = [item for item in items if needle in f"{item.brand} {item.name} {item.category} {' '.join(item.tags)}".lower()]
        if category:
            items = [item for item in items if item.category == category]
        if domain:
            items = [item for item in items if item.domain == domain]
        if not include_unavailable:
            items = [item for item in items if item.availability and item.inventory_status != "out_of_stock"]
        return items


class ProductionCatalogProvider(CatalogProvider):
    name = "production_catalog_contract"

    def list_products(self, query: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
        if not (settings.catalog_api_base_url and settings.catalog_api_token):
            raise ProviderUnavailable(
                "catalog_provider_unconfigured",
                "Production catalog provider is not configured. Set CATALOG_API_BASE_URL and CATALOG_API_TOKEN.",
            )
        raise ProviderUnavailable(
            "catalog_provider_adapter_required",
            "Production catalog contract is declared, but the retail catalog adapter implementation is not connected in this repository.",
        )


def get_catalog_provider() -> CatalogProvider:
    if settings.is_production or settings.catalog_provider == "external":
        return ProductionCatalogProvider()
    return LocalCatalogProvider()


def category_label(category: str) -> str:
    return CATEGORY_LABELS.get(category, category.replace("_", " "))


def load_catalog(query: str | None = None, category: str | None = None, domain: str | None = None, include_unavailable: bool = True) -> list[Product]:
    return get_catalog_provider().list_products(query=query, category=category, domain=domain, include_unavailable=include_unavailable)


def get_product(sku: str) -> Product | None:
    return get_catalog_provider().get_product(sku)
