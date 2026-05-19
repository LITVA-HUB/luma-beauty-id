from __future__ import annotations

from datetime import datetime, timezone

from .catalog import category_label, load_catalog
from .schemas import BeautyID, Product, RecommendationProduct, RecommendationsRequest, RecommendationsResponse

UTC = timezone.utc
NON_MEDICAL_DISCLAIMER = "Подбор основан на Beauty ID и каталоге. Это не диагностика кожи и не медицинская рекомендация."

BUDGET_MAP = {
    "entry": {"budget"},
    "mid": {"budget", "mid"},
    "premium": {"mid", "premium"},
    "luxury": {"premium"},
}

BASE_ROUTINES = {
    "minimal": ["cleanser", "moisturizer", "spf"],
    "balanced": ["cleanser", "serum", "moisturizer", "spf", "foundation", "concealer", "blush", "lip_tint"],
    "extended": ["cleanser", "serum", "moisturizer", "spf", "foundation", "concealer", "powder", "blush", "eyeshadow_palette", "mascara", "brow_gel", "lipstick", "lip_tint"],
}

FOCUS_CATEGORY_HINTS = {
    "spf": ["spf"],
    "сия": ["serum", "moisturizer", "spf", "foundation", "lip_tint", "blush"],
    "glow": ["serum", "moisturizer", "spf", "foundation", "lip_tint", "blush"],
    "мат": ["powder", "foundation", "concealer"],
    "вечер": ["foundation", "concealer", "powder", "eyeshadow_palette", "mascara", "blush", "lipstick"],
    "быстро": ["cleanser", "moisturizer", "spf", "foundation", "lip_tint"],
    "утром": ["cleanser", "serum", "moisturizer", "spf"],
    "k-beauty": ["serum", "moisturizer", "spf", "lip_tint"],
    "увлаж": ["serum", "moisturizer"],
    "без отдуш": ["cleanser", "serum", "moisturizer", "spf"],
}


def completion_for_beauty_id(beauty_id: BeautyID) -> float:
    fields = [
        beauty_id.skin_type,
        beauty_id.concerns,
        beauty_id.sensitivity,
        beauty_id.fragrance_sensitivity,
        beauty_id.preferred_finish,
        beauty_id.makeup_preferences,
        beauty_id.budget,
        beauty_id.routine_complexity,
        beauty_id.style_tags,
        beauty_id.consent,
    ]
    filled = sum(1 for value in fields if bool(value))
    return round(min(1.0, filled / len(fields)), 2)


def tags_for_beauty_id(beauty_id: BeautyID) -> list[str]:
    tags: list[str] = []
    if beauty_id.skin_type:
        tags.append(beauty_id.skin_type)
    tags.extend(beauty_id.concerns[:3])
    tags.extend(beauty_id.preferred_finish[:2])
    tags.extend(beauty_id.style_tags[:3])
    if beauty_id.fragrance_sensitivity == "avoid":
        tags.append("без отдушек")
    if beauty_id.routine_complexity == "minimal":
        tags.append("быстро утром")
    return list(dict.fromkeys(tags))[:10]


def requested_categories(beauty_id: BeautyID | None, focus: str | None) -> list[str]:
    complexity = (beauty_id.routine_complexity if beauty_id else "balanced") or "balanced"
    categories = list(BASE_ROUTINES.get(complexity, BASE_ROUTINES["balanced"]))
    normalized_focus = (focus or "").lower()
    for token, hinted in FOCUS_CATEGORY_HINTS.items():
        if token in normalized_focus:
            categories = [*hinted, *categories]
    if "макияж" in normalized_focus or "makeup" in normalized_focus:
        categories = ["foundation", "concealer", "blush", "lip_tint", *categories]
    if beauty_id and any(tag in beauty_id.makeup_preferences for tag in ["makeup", "tone", "complexion"]):
        categories = [*categories, "foundation", "concealer", "blush", "powder"]
    deduped: list[str] = []
    for category in categories:
        if category not in deduped:
            deduped.append(category)
    return deduped[:14]


def _contains_exclusion(product: Product, exclusions: list[str]) -> bool:
    haystack = " ".join([*product.ingredients, *product.tags, product.name, product.brand]).lower()
    return any(exclusion.lower() in haystack for exclusion in exclusions if exclusion)


def score_product(product: Product, beauty_id: BeautyID, category: str, focus: str | None = None) -> tuple[float, list[str], list[str]]:
    score = 44.0
    reasons: list[str] = []
    warnings: list[str] = []
    focus_text = (focus or "").lower()

    if product.category == category:
        score += 18
    if beauty_id.skin_type and beauty_id.skin_type in product.skin_types:
        score += 11
        reasons.append(f"текстура дружит с профилем {beauty_id.skin_type}")
    concern_matches = [c for c in beauty_id.concerns if c in product.concerns or c in product.tags]
    if concern_matches:
        score += min(16, 6 * len(concern_matches))
        reasons.append("учитывает ваши главные beauty-задачи")
    finish_matches = [f for f in beauty_id.preferred_finish if f in product.finishes or f in product.tags]
    if finish_matches:
        score += 8
        reasons.append(f"даёт {finish_matches[0]} finish")
    style_matches = [tag for tag in beauty_id.style_tags if tag in product.tags or tag in product.name.lower()]
    if style_matches:
        score += 4
    allowed_budget = BUDGET_MAP.get(beauty_id.budget, {"budget", "mid"})
    if product.price_segment in allowed_budget:
        score += 8
    elif beauty_id.budget == "entry" and product.price_segment == "premium":
        score -= 18
        warnings.append("выше выбранного бюджета")
    elif beauty_id.budget in {"premium", "luxury"} and product.price_segment == "budget":
        score -= 3
    if beauty_id.fragrance_sensitivity == "avoid" and any(t in {"fragrance", "scented", "perfumed"} for t in product.tags):
        score -= 30
        warnings.append("может не подойти при чувствительности к отдушкам")
    if _contains_exclusion(product, beauty_id.ingredient_exclusions):
        score -= 80
        warnings.append("есть ингредиент из списка исключений")
    if any(token in focus_text for token in ["дешев", "cheaper"]):
        if product.price_segment == "budget":
            score += 10
        if product.price_segment == "premium":
            score -= 10
    if any(token in focus_text for token in ["люкс", "premium", "luxury"]):
        if product.price_segment == "premium":
            score += 12
    if any(token in focus_text for token in ["сия", "glow"]):
        if "radiant" in product.finishes or "glow" in product.tags or "hydrating" in product.tags:
            score += 9
            reasons.append("поддерживает свежий glow-эффект")
    if any(token in focus_text for token in ["мат", "matte"]):
        if "matte" in product.finishes or "oil-control" in product.tags:
            score += 9
    if not product.availability:
        score -= 100
        warnings.append("сейчас недоступно")

    score = max(0, min(100, score))
    return score, reasons, warnings


def _reason_for(product: Product, beauty_id: BeautyID, reasons: list[str], score: float) -> str:
    if reasons:
        main = reasons[0]
    elif product.texture:
        main = f"лёгкая {product.texture} текстура хорошо встраивается в routine"
    else:
        main = "хороший match по категории и бюджету"
    sensitivity = " Аккуратно по ощущениям: начните с небольшого количества." if beauty_id.sensitivity == "high" else ""
    return f"{main}; match {int(round(score))} из 100.{sensitivity}"


def recommend_products(request: RecommendationsRequest) -> RecommendationsResponse:
    beauty_id = request.beauty_id or BeautyID(consent=True)
    categories = requested_categories(beauty_id, request.focus)
    catalog = load_catalog(include_unavailable=False)
    selected: list[RecommendationProduct] = []

    for category in categories:
        candidates = [product for product in catalog if product.category == category]
        if not candidates:
            continue
        ranked = []
        for product in candidates:
            score, reasons, warnings = score_product(product, beauty_id, category, request.focus)
            if score <= 5:
                continue
            ranked.append((score, product, reasons, warnings))
        ranked.sort(key=lambda item: (-item[0], item[1].price_value))
        if not ranked:
            continue
        score, product, reasons, warnings = ranked[0]
        alternatives = [candidate.sku for _, candidate, _, _ in ranked[1:4]]
        product_data = product.model_dump()
        product_data["warnings"] = list(dict.fromkeys([*product.warnings, *warnings]))
        selected.append(
            RecommendationProduct(
                **product_data,
                match_score=int(round(score)),
                reason=_reason_for(product, beauty_id, reasons, score),
                routine_step=category_label(category),
                alternatives=alternatives,
            )
        )

    seen = {item.sku for item in selected}
    extra_ranked = []
    for product in catalog:
        if product.sku in seen:
            continue
        score, reasons, warnings = score_product(product, beauty_id, product.category, request.focus)
        if score > 35:
            extra_ranked.append((score, product, reasons, warnings))
    extra_ranked.sort(key=lambda item: (-item[0], item[1].price_value))
    products = list(selected)
    for score, product, reasons, warnings in extra_ranked:
        if len(products) >= request.limit:
            break
        product_data = product.model_dump()
        product_data["warnings"] = list(dict.fromkeys([*product.warnings, *warnings]))
        products.append(
            RecommendationProduct(
                **product_data,
                match_score=int(round(score)),
                reason=_reason_for(product, beauty_id, reasons, score),
                routine_step=category_label(product.category),
                alternatives=[],
            )
        )

    hero = max(products, key=lambda item: item.match_score, default=None)
    explanation = "Я собрала подборку по Beauty ID: сначала базовые шаги routine, затем продукты для финиша и настроения."
    if request.focus:
        explanation = f"Я уточнила подборку под запрос «{request.focus}» и оставила только товары из текущего каталога."
    return RecommendationsResponse(
        hero=hero,
        routine=selected,
        products=products[: request.limit],
        explanation=explanation,
        disclaimer=NON_MEDICAL_DISCLAIMER,
        generated_at=datetime.now(UTC),
        provider="deterministic",
    )
