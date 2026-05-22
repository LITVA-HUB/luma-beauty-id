from __future__ import annotations

from datetime import datetime

from fastapi import HTTPException

from .catalog import load_catalog
from .dependencies import get_store
from .provider_errors import ProviderUnavailable
from .schemas import (
    ActiveSelectionItem,
    ActiveSelectionItemRequest,
    ActiveSelectionResponse,
    AdvisorRequest,
    AdvisorSelectionProduct,
    Product,
    SavedRoutineResponse,
)
from .security import utcnow


def products_by_sku() -> dict[str, Product]:
    return {item.sku: item for item in load_catalog(include_unavailable=True)}


def saved_routine_response(account_id: str) -> SavedRoutineResponse:
    stored = get_store().get_saved_routine(account_id)
    if not stored:
        return SavedRoutineResponse(skus=[], products=[], updated_at=None)
    skus, updated_at = stored
    products = products_by_sku()
    valid_skus = [sku for sku in skus if sku in products]
    return SavedRoutineResponse(skus=valid_skus, products=[products[sku] for sku in valid_skus], updated_at=updated_at)


def validate_saved_routine_skus(skus: list[str]) -> list[str]:
    products = products_by_sku()
    valid: list[str] = []
    invalid: list[str] = []
    for sku in skus:
        if sku in products:
            valid.append(sku)
        else:
            invalid.append(sku)
    if invalid:
        raise HTTPException(status_code=400, detail="invalid_saved_routine_sku")
    return valid


def validate_selection_items(items: list[ActiveSelectionItemRequest]) -> list[dict[str, object]]:
    products = products_by_sku()
    seen: set[str] = set()
    valid: list[dict[str, object]] = []
    now = utcnow()
    for item in items:
        if item.sku not in products:
            raise HTTPException(status_code=400, detail="invalid_active_selection_sku")
        if item.sku in seen:
            continue
        seen.add(item.sku)
        added_at = item.added_at or now
        valid.append(
            {
                "sku": item.sku,
                "source": item.source,
                "routine_step": item.routine_step,
                "reason": item.reason,
                "match_score": item.match_score,
                "added_at": added_at.isoformat(),
                "updated_at": (item.updated_at or now).isoformat(),
                "locked": item.locked,
                "metadata": item.metadata,
            }
        )
    return valid


def selection_response(account_id: str, added_count: int = 0, already_in_selection_count: int = 0) -> ActiveSelectionResponse:
    stored = get_store().get_active_selection(account_id)
    if not stored:
        return ActiveSelectionResponse()
    raw_items, updated_at = stored
    products = products_by_sku()
    items: list[ActiveSelectionItem] = []
    source_summary: dict[str, int] = {}
    match_scores: list[int] = []
    for raw in raw_items:
        sku = str(raw.get("sku", "")).strip().upper()
        product = products.get(sku)
        if not product:
            continue
        source = str(raw.get("source") or "manual")
        if source not in {"advisor", "recommendations", "manual", "cart", "saved_routine", "scan"}:
            source = "manual"
        source_summary[source] = source_summary.get(source, 0) + 1
        score = raw.get("match_score")
        if isinstance(score, int):
            match_scores.append(score)
        added_at_raw = raw.get("added_at")
        updated_at_raw = raw.get("updated_at")
        try:
            added_at = utcnow() if not added_at_raw else datetime.fromisoformat(str(added_at_raw))
        except ValueError:
            added_at = utcnow()
        parsed_updated_at = None
        if updated_at_raw:
            try:
                parsed_updated_at = datetime.fromisoformat(str(updated_at_raw))
            except ValueError:
                parsed_updated_at = None
        items.append(
            ActiveSelectionItem(
                sku=sku,
                product=product,
                source=source,  # type: ignore[arg-type]
                routine_step=raw.get("routine_step") if isinstance(raw.get("routine_step"), str) else None,
                reason=raw.get("reason") if isinstance(raw.get("reason"), str) else None,
                match_score=score if isinstance(score, int) else None,
                added_at=added_at,
                updated_at=parsed_updated_at,
                locked=bool(raw.get("locked")),
                metadata=raw.get("metadata") if isinstance(raw.get("metadata"), dict) else {},
            )
        )
    total = sum(item.product.price_value for item in items)
    average_match = round(sum(match_scores) / len(match_scores), 1) if match_scores else None
    return ActiveSelectionResponse(
        items=items,
        skus=[item.sku for item in items],
        count=len(items),
        total_price=total,
        average_match=average_match,
        updated_at=updated_at,
        source_summary=source_summary,
        added_count=added_count,
        already_in_selection_count=already_in_selection_count,
    )


def merge_active_selection(account_id: str, incoming: list[ActiveSelectionItemRequest]) -> tuple[int, int]:
    valid_incoming = validate_selection_items(incoming)
    store = get_store()
    stored = store.get_active_selection(account_id)
    existing = list(stored[0]) if stored else []
    by_sku = {str(item.get("sku", "")).strip().upper(): index for index, item in enumerate(existing)}
    added = 0
    duplicate = 0
    for item in valid_incoming:
        sku = str(item["sku"])
        if sku in by_sku:
            duplicate += 1
            old = dict(existing[by_sku[sku]])
            old.update({key: value for key, value in item.items() if key != "added_at" and value is not None})
            old["added_at"] = old.get("added_at") or item.get("added_at")
            old["updated_at"] = utcnow().isoformat()
            existing[by_sku[sku]] = old
        else:
            by_sku[sku] = len(existing)
            existing.append(item)
            added += 1
    store.save_active_selection(account_id, existing)
    return added, duplicate


def advisor_selection_context(account_id: str, payload: AdvisorRequest) -> tuple[list[AdvisorSelectionProduct], list[str]]:
    try:
        products = products_by_sku()
    except ProviderUnavailable:
        return payload.current_selection, payload.current_skus
    selection: list[AdvisorSelectionProduct] = []
    skus: list[str] = []

    def append_product(product: Product, routine_step: str | None = None) -> None:
        if product.sku in skus:
            return
        skus.append(product.sku)
        selection.append(
            AdvisorSelectionProduct(
                sku=product.sku,
                brand=product.brand,
                name=product.name,
                category=product.category,
                product_type=product.product_type,
                price_value=product.price_value,
                currency=product.currency,
                routine_step=routine_step,
            )
        )

    stored_selection = get_store().get_active_selection(account_id)
    if stored_selection:
        for item in stored_selection[0][:24]:
            product = products.get(str(item.get("sku", "")).strip().upper())
            if product:
                append_product(product, item.get("routine_step") if isinstance(item.get("routine_step"), str) else None)

    for item in payload.current_selection[:20]:
        product = products.get(item.sku)
        if product:
            append_product(product, item.routine_step)

    merged_skus = list(skus)
    for sku in [*payload.current_skus, *[item.sku for item in payload.current_cart]]:
        normalized = sku.strip().upper()
        if normalized and normalized not in merged_skus:
            merged_skus.append(normalized)
    return selection, merged_skus
