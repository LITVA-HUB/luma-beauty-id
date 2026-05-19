from __future__ import annotations

import asyncio
import json
import logging
import re
from abc import ABC, abstractmethod
from typing import Any

import httpx
from pydantic import BaseModel, Field, ValidationError, field_validator

from .catalog import get_product, load_catalog
from .config import settings
from .provider_errors import ProviderUnavailable
from .recommendations import recommend_products
from .schemas import AdvisorAction, AdvisorMessage, AdvisorRequest, AdvisorResponse, BeautyID, Product, RecommendationProduct, RecommendationsRequest
from .security import utcnow

logger = logging.getLogger("luma.advisor")

SYSTEM_PROMPT = """
You are Luma Beauty ID, a premium beauty retail concierge for an iPhone app.

Tone:
- Speak briefly, warmly and confidently.
- Sound like a premium beauty consultant, not a doctor and not a generic chatbot.
- Keep answers useful, concrete and product-aware.
- Prefer compact Russian when the user writes in Russian. Avoid hype, filler and long essays.

Safety boundaries:
- This is cosmetic product matching, not medical care.
- Do not diagnose skin conditions.
- Do not provide treatment plans or medical advice.
- Do not claim that AI detected disease, acne, dermatitis, rosacea or any condition.
- Do not use fake certainty.
- If the user asks for diagnosis, treatment or severe symptoms, refuse gently and suggest a qualified professional.

Catalog grounding:
- You may recommend ONLY SKUs included in allowed_products.
- Never invent products, brands, prices, reviews or product claims.
- Respect Beauty ID budget, sensitivity, fragrance preference and ingredient exclusions.
- Treat current_selection as the current personalized set.
- current_selection, shelf, current_cart and saved routine are separate states.
- Do not recommend the same SKU again unless explaining it is already selected.
- When adding products, preserve existing choices and suggest additions or explicit alternatives.
- If you propose replacing an existing product, say clearly which item is the alternative to replace.
- If the catalog subset is limited, say so and suggest a refinement.
- When the user asks "какие", "например", "назови", "which", or asks for examples, name 1-3 concrete products from allowed_products by brand + product name.
- Keep recommended_skus aligned with the product names mentioned in the answer.
- Avoid generic answers like "I picked light products" when specific product examples are available.

Action rules:
- Never say "добавила в корзину", "очистила корзину", "сохранила" or any completed state unless the app has already applied a structured action. You are only returning actions.
- For executable commands, return an action and a short pending message: "Сейчас добавлю в полку.", "Сейчас добавлю в список к покупке." or "Сейчас очищу корзину."
- For destructive or ambiguous changes, return a confirmation action or ask a clarification. Do not silently remove, clear or replace.
- Clear cart is executable without confirmation only when the user explicitly asks to clear the cart.
- "очисти" without saying cart/корзина or selection/подборка is ambiguous: ask what to clear.
- "добавь это в полку", "добавь в мою полку", "сохрани в хочу попробовать" should become shelf actions, not cart actions.
- "добавь это в корзину", "закинь в корзину", "беру эти", "добавь набор к покупке" should become cart actions, not shelf actions.
- "сделай дешевле" should suggest alternatives or replacements, not silently delete existing choices.
- Use add_products_to_selection for adding to active selection. Use add_current_routine_to_shelf/add_product_to_shelf/mark_product_wanted for shelf. Use add_products_to_cart/add_current_routine_to_cart for cart.

Return one valid JSON object only. Do not use markdown, code fences or extra prose. Use this shape:
{
  "message": "short answer in the user's language",
  "actions": [
    {"type": "add_products_to_selection", "skus": ["SKU from allowed_products only"], "old_sku": null, "new_sku": null, "reason": "why", "requires_confirmation": false}
  ],
  "quick_actions": ["short chip", "short chip"],
  "recommended_skus": ["SKU from allowed_products only"],
  "routine_steps": ["cleanser", "serum", "SPF"],
  "why_this_works": "one short explanation",
  "safety_note": null
}
""".strip()

MEDICAL_TOKENS = {
    "диагноз", "диагност", "вылеч", "лечить", "лечение", "дерматит", "розаце", "экзема", "псориаз", "инфекция", "аллергия",
    "сильный зуд", "жжение", "боль", "сыпь", "кров", "гной", "воспаление",
    "diagnose", "diagnosis", "treat", "treatment", "dermatitis", "rosacea", "eczema", "psoriasis", "infection", "allergy",
    "rash", "severe itch", "burning", "pain", "bleeding", "pus", "inflammation",
}
MEDICAL_EXACT_TOKENS = {"боль", "pain", "rash", "pus"}

QUICK_ACTIONS = ["дешевле", "сияние", "без отдушек", "SPF", "K-beauty", "быстро утром", "матовый финиш", "люкс"]

INTERNAL_PROMPT_MARKERS = (
    "Контекст предыдущего диалога",
    "Новое сообщение пользователя",
    "Ответь именно",
    "allowed_products",
    "system prompt",
    "developer message",
    "internal context",
    "prompt_version",
    "JSON schema",
    "Ты ассистент",
    "You are",
)

ADVISOR_JSON_SCHEMA: dict[str, object] = {
    "name": "luma_advisor_response",
    "strict": True,
    "schema": {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "message": {"type": "string"},
            "quick_actions": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
            "actions": {
                "type": "array",
                "maxItems": 6,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "type": {
                            "type": "string",
                            "enum": [
                                "add_products",
                                "add_products_to_selection",
                                "remove_products_from_selection",
                                "clear_selection",
                                "suggest_replace_product",
                                "replace_product",
                                "replace_product_confirmed",
                                "show_alternatives",
                                "explain_selection",
                                "refine_budget",
                                "refine_fragrance_free",
                                "refine_lighter_texture",
                                "refine_more_glow",
                                "refine_premium",
                                "remove_product_suggestion",
                                "save_routine_suggestion",
                                "save_selection_as_routine",
                                "save_current_routine",
                                "load_saved_routine",
                                "replace_saved_routine_confirmed",
                                "add_current_routine_to_shelf",
                                "add_product_to_shelf",
                                "mark_product_wanted",
                                "mark_product_owned",
                                "mark_product_buy_later",
                                "mark_product_did_not_fit",
                                "add_current_routine_to_cart",
                                "add_products_to_cart",
                                "remove_products_from_cart",
                                "clear_cart",
                                "move_selection_to_cart",
                                "add_selection_to_cart",
                            ],
                        },
                        "skus": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
                        "old_sku": {"type": ["string", "null"]},
                        "new_sku": {"type": ["string", "null"]},
                        "reason": {"type": ["string", "null"]},
                        "requires_confirmation": {"type": "boolean"},
                    },
                    "required": ["type", "skus", "old_sku", "new_sku", "reason", "requires_confirmation"],
                },
            },
            "recommended_skus": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
            "routine_steps": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
            "why_this_works": {"type": ["string", "null"]},
            "safety_note": {"type": ["string", "null"]},
        },
        "required": ["message", "quick_actions", "actions", "recommended_skus", "routine_steps", "why_this_works", "safety_note"],
    },
}


def contains_internal_prompt_marker(text: str) -> bool:
    return any(marker.lower() in text.lower() for marker in INTERNAL_PROMPT_MARKERS)


def clean_display_message(message: str) -> str:
    text = message.strip()
    if not contains_internal_prompt_marker(text):
        return text
    match = re.search(
        r"Новое сообщение пользователя:\s*(?P<message>.*?)(?:\n\s*\n\s*Ответь именно|\Z)",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if match:
        extracted = match.group("message").strip()
        if extracted and not contains_internal_prompt_marker(extracted):
            return extracted[:1200]
    return re.sub(r"\s+", " ", text).strip()[:1200]


class LLMAdvisorPayload(BaseModel):
    message: str = Field(min_length=1, max_length=900)
    actions: list[AdvisorAction] = Field(default_factory=list)
    quick_actions: list[str] = Field(default_factory=list)
    recommended_skus: list[str] = Field(default_factory=list)
    routine_steps: list[str] = Field(default_factory=list)
    why_this_works: str | None = Field(default=None, max_length=900)
    safety_note: str | None = Field(default=None, max_length=160)

    @field_validator("quick_actions", "recommended_skus", "routine_steps", mode="before")
    @classmethod
    def normalize_list(cls, value: Any) -> list[str]:
        if value is None:
            return []
        if not isinstance(value, list):
            return []
        result: list[str] = []
        for item in value:
            text = str(item).strip()
            if text and text not in result:
                result.append(text)
        return result


def is_medical_intent(message: str) -> bool:
    lower = message.lower()
    for token in MEDICAL_TOKENS:
        if token in MEDICAL_EXACT_TOKENS:
            if re.search(rf"(?<![\wа-яё]){re.escape(token)}(?![\wа-яё])", lower):
                return True
        elif token in lower:
            return True
    return False


def _catalog_grounded(recommendations: list[RecommendationProduct]) -> list[RecommendationProduct]:
    known = {item.sku for item in load_catalog(include_unavailable=False)}
    return [item for item in recommendations if item.sku in known]


def _respects_exclusions(item: RecommendationProduct, beauty_id: BeautyID) -> bool:
    haystack = " ".join([item.name, item.brand, *item.ingredients, *item.tags, *item.warnings]).lower()
    return not any(token.lower() in haystack for token in beauty_id.ingredient_exclusions if token)


def _medical_refusal(provider: str) -> AdvisorResponse:
    answer = (
        "Я не могу ставить диагнозы или назначать лечение. Могу помочь с косметической routine по ощущениям, "
        "текстурам, финишу и предпочтениям. Если есть сильное раздражение, боль, зуд или стойкие симптомы, лучше обратиться к специалисту."
    )
    return AdvisorResponse(
        answer=answer,
        messages=[AdvisorMessage(role="assistant", text=answer, created_at=utcnow())],
        quick_actions=["мягкий набор", "без отдушек", "SPF", "минимум шагов"],
        recommendations=[],
        recommended_skus=[],
        routine_steps=[],
        why_this_works="Это beauty advisor: он помогает подобрать косметические текстуры и routine, но не заменяет медицинскую консультацию.",
        safety_note="medical_boundary",
        prompt_version=settings.advisor_prompt_version,
        provider=provider,
    )


def _response_from_recommendations(
    *,
    answer: str,
    recommendations: list[RecommendationProduct],
    provider: str,
    actions: list[AdvisorAction] | None = None,
    quick_actions: list[str] | None = None,
    why_this_works: str | None = None,
    routine_steps: list[str] | None = None,
    safety_note: str | None = None,
    fallback_reason: str | None = None,
) -> AdvisorResponse:
    skus = [item.sku for item in recommendations]
    steps = routine_steps or [item.routine_step for item in recommendations[:5]]
    response_actions = actions
    if response_actions is None and skus:
        response_actions = [AdvisorAction(type="add_products_to_selection", skus=skus[:6], reason="добавить к текущей подборке", requires_confirmation=False)]
    return AdvisorResponse(
        answer=answer,
        messages=[AdvisorMessage(role="assistant", text=answer, created_at=utcnow())],
        quick_actions=quick_actions or QUICK_ACTIONS,
        actions=response_actions or [],
        recommendations=recommendations,
        recommended_skus=skus,
        routine_steps=steps,
        why_this_works=why_this_works,
        safety_note=safety_note,
        fallback_reason=fallback_reason,
        prompt_version=settings.advisor_prompt_version,
        provider=provider,
    )


class AdvisorProvider(ABC):
    name: str

    @abstractmethod
    async def respond(self, request: AdvisorRequest) -> AdvisorResponse:
        raise NotImplementedError


class DeterministicAdvisorProvider(AdvisorProvider):
    name = "deterministic_fallback"

    async def respond(self, request: AdvisorRequest) -> AdvisorResponse:
        beauty_id = request.beauty_id or BeautyID(consent=True)
        if is_medical_intent(request.message):
            return _medical_refusal(self.name)

        recs = recommend_products(RecommendationsRequest(beauty_id=beauty_id, focus=request.message, limit=8, filters={}))
        grounded = _catalog_grounded(recs.products)
        grounded = [item for item in grounded if _respects_exclusions(item, beauty_id)]
        hero = grounded[0] if grounded else None
        if hero:
            answer = (
                f"Я бы начала с {hero.brand} {hero.name}: {hero.reason} "
                "Это косметическое совпадение по Beauty ID, не диагностика. Могу сделать набор дешевле, мягче по отдушкам или более сияющим."
            )
            why = "Подбор держится на вашем Beauty ID, бюджете, желаемом финише и текущем каталоге."
        else:
            answer = "По текущему каталогу нет идеального совпадения. Я могу сузить запрос по бюджету, отдушкам, SPF или финишу и собрать более точный набор."
            why = "Каталог и ограничения Beauty ID сейчас дают мало уверенных совпадений."
        return _response_from_recommendations(
            answer=answer,
            recommendations=grounded,
            provider=self.name,
            why_this_works=why,
        )


class OpenRouterAdvisorProvider(AdvisorProvider):
    name = "openrouter"

    def _ensure_configured(self) -> None:
        if not settings.openrouter_api_key:
            raise ProviderUnavailable(
                "advisor_provider_unconfigured",
                "OpenRouter advisor is not configured. Set OPENROUTER_API_KEY on the backend.",
                fallback_allowed=settings.is_non_production,
            )
        if not settings.openrouter_model:
            raise ProviderUnavailable(
                "advisor_provider_unconfigured",
                "OpenRouter advisor model is not configured. Set OPENROUTER_MODEL on the backend.",
                fallback_allowed=settings.is_non_production,
            )
        if settings.is_production and not settings.openrouter_base_url.startswith("https://"):
            raise ProviderUnavailable(
                "advisor_provider_unconfigured",
                "OPENROUTER_BASE_URL must use https in production.",
                fallback_allowed=False,
            )

    def _catalog_subset(self, request: AdvisorRequest, beauty_id: BeautyID) -> list[RecommendationProduct]:
        seed = recommend_products(RecommendationsRequest(beauty_id=beauty_id, focus=request.message, limit=12, filters={}))
        products: list[RecommendationProduct] = [item for item in seed.products if _respects_exclusions(item, beauty_id)]
        seen = {item.sku for item in products}
        for sku in request.current_skus[:8]:
            product = get_product(sku)
            if product and product.availability and product.inventory_status != "out_of_stock" and product.sku not in seen:
                score = 72
                data = product.model_dump()
                products.append(RecommendationProduct(**data, match_score=score, reason="уже есть в текущем product context", routine_step=product.category, alternatives=[]))
                seen.add(product.sku)
        return products[:16]

    def _safe_beauty_id_summary(self, beauty_id: BeautyID) -> dict[str, object]:
        return {
            "skin_type": beauty_id.skin_type,
            "concerns": beauty_id.concerns[:6],
            "sensitivity": beauty_id.sensitivity,
            "fragrance_sensitivity": beauty_id.fragrance_sensitivity,
            "preferred_finish": beauty_id.preferred_finish[:4],
            "makeup_preferences": beauty_id.makeup_preferences[:6],
            "budget": beauty_id.budget,
            "ingredient_exclusions": beauty_id.ingredient_exclusions[:10],
            "routine_complexity": beauty_id.routine_complexity,
            "style_tags": beauty_id.style_tags[:6],
        }

    def _safe_product(self, product: RecommendationProduct) -> dict[str, object]:
        return {
            "sku": product.sku,
            "brand": product.brand,
            "name": product.name,
            "category": product.category,
            "domain": product.domain,
            "price_value": product.price_value,
            "currency": product.currency,
            "availability": product.availability,
            "inventory_status": product.inventory_status,
            "tags": product.tags[:10],
            "ingredients": product.ingredients[:12],
            "warnings": product.warnings[:8],
            "routine_step": product.routine_step,
            "match_reason": product.reason,
        }

    def _safe_current_product(self, product: object) -> dict[str, object]:
        return {
            "sku": getattr(product, "sku", None),
            "brand": getattr(product, "brand", None),
            "name": getattr(product, "name", None),
            "category": getattr(product, "category", None),
            "product_type": getattr(product, "product_type", None),
            "price_value": getattr(product, "price_value", None),
            "currency": getattr(product, "currency", None),
            "routine_step": getattr(product, "routine_step", None),
        }

    def _response_format_ladder(self) -> list[str]:
        preferred = (settings.openrouter_response_format or "json_schema").strip().lower()
        candidates = [preferred, "json_schema", "json_object", "none"]
        result: list[str] = []
        for item in candidates:
            normalized = item if item in {"json_schema", "json_object", "none"} else "json_schema"
            if normalized not in result:
                result.append(normalized)
        return result

    def _request_payload(self, request: AdvisorRequest, beauty_id: BeautyID, allowed_products: list[RecommendationProduct], response_format: str) -> dict[str, object]:
        recent_history = [
            {"role": item.role, "content": item.content}
            for item in request.conversation_history[-8:]
            if item.role in {"user", "assistant"} and item.content and not contains_internal_prompt_marker(item.content)
        ]
        user_context = {
            "user_message": request.message,
            "recent_history": recent_history,
            "beauty_id_summary": self._safe_beauty_id_summary(beauty_id),
            "current_selection": [self._safe_current_product(item) for item in request.current_selection[:20]],
            "current_cart": [self._safe_current_product(item) for item in request.current_cart[:20]],
            "current_skus": request.current_skus[:30],
            "allowed_products": [self._safe_product(item) for item in allowed_products],
            "response_language_hint": "match the user's language",
            "prompt_version": settings.advisor_prompt_version,
        }
        system_prompt = SYSTEM_PROMPT
        if response_format == "json_object":
            system_prompt += "\nReturn valid JSON only. The top-level value must be an object with the required keys."
        elif response_format == "none":
            system_prompt += "\nThe API may not enforce JSON mode here, so you must still return a single valid JSON object only."
        payload: dict[str, object] = {
            "model": settings.openrouter_model,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": json.dumps(user_context, ensure_ascii=False)},
            ],
            "temperature": 0.22,
            "max_tokens": 650,
        }
        if response_format == "json_schema":
            payload["response_format"] = {"type": "json_schema", "json_schema": ADVISOR_JSON_SCHEMA}
        elif response_format == "json_object":
            payload["response_format"] = {"type": "json_object"}
        return payload

    async def _send_to_openrouter(self, payload: dict[str, object]) -> dict[str, object]:
        self._ensure_configured()
        if not settings.openrouter_api_key:
            raise ProviderUnavailable(
                "advisor_provider_unconfigured",
                "OpenRouter advisor is not configured. Set OPENROUTER_API_KEY on the backend.",
                fallback_allowed=settings.is_non_production,
            )
        if not settings.openrouter_model:
            raise ProviderUnavailable(
                "advisor_provider_unconfigured",
                "OpenRouter advisor model is not configured. Set OPENROUTER_MODEL on the backend.",
                fallback_allowed=settings.is_non_production,
            )
        url = f"{settings.openrouter_base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {settings.openrouter_api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": settings.public_api_base_url,
            "X-Title": "Luma Beauty ID",
        }
        max_retries = max(0, min(settings.openrouter_max_retries, 5))
        timeout = httpx.Timeout(float(settings.openrouter_timeout_seconds))
        last_code = "advisor_provider_error"
        for attempt in range(max_retries + 1):
            try:
                async with httpx.AsyncClient(timeout=timeout) as client:
                    response = await client.post(url, headers=headers, json=payload)
                if response.status_code >= 400:
                    if response.status_code in {401, 403}:
                        last_code = "advisor_provider_auth_failed"
                        raise ProviderUnavailable(last_code, "OpenRouter authentication failed. Check the backend secret and account access.", fallback_allowed=False)
                    if response.status_code in {400, 422}:
                        last_code = "advisor_provider_response_format_error"
                        raise ProviderUnavailable(last_code, "OpenRouter rejected the advisor request format; trying a compatible JSON mode when possible.", fallback_allowed=True)
                    last_code = "advisor_provider_rate_limited" if response.status_code == 429 else "advisor_provider_http_error"
                    if response.status_code in {408, 409, 425, 429} or response.status_code >= 500:
                        raise httpx.HTTPStatusError("OpenRouter transient status", request=response.request, response=response)
                    raise ProviderUnavailable(last_code, f"OpenRouter request failed with status {response.status_code}.", fallback_allowed=True)
                return response.json()
            except ProviderUnavailable:
                raise
            except httpx.TimeoutException as exc:
                last_code = "advisor_provider_timeout"
                logger.warning(
                    "advisor_openrouter_request_failed",
                    extra={"provider": self.name, "prompt_version": settings.advisor_prompt_version, "attempt": attempt + 1, "code": last_code},
                )
                if attempt >= max_retries:
                    raise ProviderUnavailable(last_code, "OpenRouter advisor request timed out. Using catalog-grounded fallback when allowed.", fallback_allowed=True) from exc
                await asyncio.sleep(min(0.2 * (2 ** attempt), 1.2))
            except httpx.TransportError as exc:
                last_code = "advisor_provider_network_error"
                logger.warning(
                    "advisor_openrouter_request_failed",
                    extra={"provider": self.name, "prompt_version": settings.advisor_prompt_version, "attempt": attempt + 1, "code": last_code},
                )
                if attempt >= max_retries:
                    raise ProviderUnavailable(last_code, "OpenRouter advisor network request failed. Using catalog-grounded fallback when allowed.", fallback_allowed=True) from exc
                await asyncio.sleep(min(0.2 * (2 ** attempt), 1.2))
            except (httpx.HTTPStatusError, ValueError) as exc:
                logger.warning(
                    "advisor_openrouter_request_failed",
                    extra={"provider": self.name, "prompt_version": settings.advisor_prompt_version, "attempt": attempt + 1, "code": last_code},
                )
                if attempt >= max_retries:
                    raise ProviderUnavailable(last_code, "OpenRouter advisor request failed. Using catalog-grounded fallback when allowed.", fallback_allowed=True) from exc
                await asyncio.sleep(min(0.2 * (2 ** attempt), 1.2))
        raise ProviderUnavailable(last_code, "OpenRouter advisor request failed.", fallback_allowed=True)

    def _content_from_response(self, response: dict[str, object]) -> str:
        choices = response.get("choices")
        if not isinstance(choices, list) or not choices:
            raise ProviderUnavailable("advisor_provider_invalid_response", "OpenRouter response did not include choices.", fallback_allowed=True)
        first = choices[0]
        if not isinstance(first, dict):
            raise ProviderUnavailable("advisor_provider_invalid_response", "OpenRouter response shape was invalid.", fallback_allowed=True)
        message = first.get("message")
        if not isinstance(message, dict):
            raise ProviderUnavailable("advisor_provider_invalid_response", "OpenRouter response did not include a message.", fallback_allowed=True)
        content = message.get("content")
        if not isinstance(content, str) or not content.strip():
            raise ProviderUnavailable("advisor_provider_invalid_response", "OpenRouter response content was empty.", fallback_allowed=True)
        return content.strip()

    def _parse_llm_json(self, content: str) -> LLMAdvisorPayload:
        cleaned = content.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.IGNORECASE).strip()
            cleaned = re.sub(r"\s*```$", "", cleaned).strip()
        try:
            data = json.loads(cleaned)
        except json.JSONDecodeError:
            match = re.search(r"\{.*\}", cleaned, flags=re.DOTALL)
            if not match:
                raise ProviderUnavailable("advisor_provider_invalid_json", "OpenRouter response was not valid JSON.", fallback_allowed=True) from None
            try:
                data = json.loads(match.group(0))
            except json.JSONDecodeError as exc:
                raise ProviderUnavailable("advisor_provider_invalid_json", "OpenRouter response JSON could not be repaired safely.", fallback_allowed=True) from exc
        try:
            return LLMAdvisorPayload.model_validate(data)
        except ValidationError as exc:
            raise ProviderUnavailable("advisor_provider_invalid_schema", "OpenRouter response did not match advisor schema.", fallback_allowed=True) from exc

    def _recommendations_from_skus(self, skus: list[str], allowed_products: list[RecommendationProduct], beauty_id: BeautyID) -> list[RecommendationProduct]:
        allowed_by_sku = {item.sku: item for item in allowed_products if _respects_exclusions(item, beauty_id)}
        result: list[RecommendationProduct] = []
        for raw_sku in skus:
            sku = raw_sku.strip()
            item = allowed_by_sku.get(sku)
            if item and item.sku not in {existing.sku for existing in result}:
                result.append(item)
        return result[:8]

    def _safe_actions(self, actions: list[AdvisorAction], allowed_products: list[RecommendationProduct], request: AdvisorRequest) -> list[AdvisorAction]:
        allowed = {item.sku for item in allowed_products}
        known_catalog = {item.sku for item in load_catalog(include_unavailable=False)}
        current = {sku.strip().upper() for sku in request.current_skus if sku.strip()}
        current_selection = {item.sku.strip().upper() for item in request.current_selection if item.sku.strip()}
        current_cart = {item.sku.strip().upper() for item in request.current_cart if item.sku.strip()}
        result: list[AdvisorAction] = []
        for action in actions[:6]:
            if action.type in {"add_products", "add_products_to_selection"}:
                skus = [sku for sku in action.skus if sku in allowed]
                if skus:
                    result.append(action.model_copy(update={"type": "add_products_to_selection", "skus": skus, "requires_confirmation": False}))
            elif action.type in {"add_product_to_shelf", "mark_product_wanted", "mark_product_owned", "mark_product_buy_later", "mark_product_did_not_fit"}:
                skus = [sku for sku in action.skus if sku in known_catalog or sku in allowed or sku in current_selection]
                if skus:
                    result.append(action.model_copy(update={"skus": skus[:8], "requires_confirmation": False}))
            elif action.type == "add_current_routine_to_shelf":
                skus = [sku for sku in action.skus if sku in current_selection and sku in known_catalog]
                if not skus:
                    skus = [item.sku for item in request.current_selection if item.sku in known_catalog]
                if skus:
                    result.append(action.model_copy(update={"skus": skus[:8], "requires_confirmation": False}))
            elif action.type == "add_products_to_cart":
                skus = [sku for sku in action.skus if sku in known_catalog]
                if not skus and current_selection:
                    skus = [sku for sku in request.current_skus if sku in current_selection and sku in known_catalog]
                if skus:
                    result.append(action.model_copy(update={"skus": skus[:8], "requires_confirmation": False}))
            elif action.type in {"add_selection_to_cart", "add_current_routine_to_cart"}:
                skus = [sku for sku in action.skus if sku in current_selection and sku in known_catalog]
                if not skus:
                    skus = [item.sku for item in request.current_selection if item.sku in known_catalog]
                if skus:
                    result.append(action.model_copy(update={"skus": skus[:8], "requires_confirmation": False}))
            elif action.type in {"move_selection_to_cart"}:
                skus = [item.sku for item in request.current_selection if item.sku in known_catalog]
                if skus:
                    result.append(action.model_copy(update={"type": "add_selection_to_cart", "skus": skus[:8], "requires_confirmation": False}))
            elif action.type == "remove_products_from_cart":
                skus = [sku for sku in action.skus if sku in current_cart]
                if skus:
                    result.append(action.model_copy(update={"skus": skus, "requires_confirmation": action.requires_confirmation}))
            elif action.type == "clear_cart":
                result.append(action.model_copy(update={"skus": [], "requires_confirmation": action.requires_confirmation}))
            elif action.type == "remove_products_from_selection":
                skus = [sku for sku in action.skus if sku in current_selection or sku in current]
                if skus:
                    result.append(action.model_copy(update={"skus": skus, "requires_confirmation": action.requires_confirmation}))
            elif action.type == "clear_selection":
                result.append(action.model_copy(update={"skus": [], "requires_confirmation": True if action.requires_confirmation else False}))
            elif action.type in {"suggest_replace_product", "replace_product", "replace_product_confirmed"}:
                new_sku = action.new_sku if action.new_sku in allowed else None
                old_sku = action.old_sku if action.old_sku in current or action.old_sku in known_catalog else None
                if new_sku and old_sku:
                    result.append(action.model_copy(update={"type": "suggest_replace_product", "old_sku": old_sku, "new_sku": new_sku, "skus": [new_sku], "requires_confirmation": action.type != "replace_product_confirmed"}))
            elif action.type == "show_alternatives":
                skus = [sku for sku in action.skus if sku in allowed or sku in current]
                if skus:
                    result.append(action.model_copy(update={"skus": skus, "requires_confirmation": False}))
            elif action.type == "remove_product_suggestion":
                old_sku = action.old_sku if action.old_sku in current or action.old_sku in known_catalog else None
                if old_sku:
                    result.append(action.model_copy(update={"old_sku": old_sku, "requires_confirmation": True}))
            elif action.type in {"explain_selection", "refine_budget", "refine_fragrance_free", "refine_lighter_texture", "refine_more_glow", "refine_premium"}:
                result.append(action.model_copy(update={"requires_confirmation": False}))
            elif action.type in {"save_routine_suggestion", "save_selection_as_routine", "save_current_routine", "load_saved_routine", "replace_saved_routine_confirmed"}:
                result.append(action.model_copy(update={"requires_confirmation": action.type in {"save_routine_suggestion", "replace_saved_routine_confirmed"}}))
        return result

    def _intent_actions(self, request: AdvisorRequest) -> list[AdvisorAction]:
        text = request.message.lower()
        cart_words = {"корзин", "cart"}
        shelf_words = {"полк", "хочу попробовать", "на пробу"}
        add_words = {"добав", "закин", "полож", "беру", "возьму"}
        clear_words = {"очист", "убери всё", "удали всё", "сброс"}
        selection_words = {"подбор", "рутину", "выбран", "selection"}
        has_cart = any(word in text for word in cart_words)
        has_shelf = any(word in text for word in shelf_words)
        has_add = any(word in text for word in add_words)
        has_clear = any(word in text for word in clear_words)
        has_selection = any(word in text for word in selection_words)

        if has_shelf and has_add and request.current_selection:
            return [
                AdvisorAction(
                    type="add_current_routine_to_shelf",
                    skus=[item.sku for item in request.current_selection[:8]],
                    reason="сохранить текущий набор в полку как «Хочу попробовать»",
                    requires_confirmation=False,
                )
            ]
        if has_cart and has_clear:
            return [AdvisorAction(type="clear_cart", reason="явная команда пользователя очистить корзину", requires_confirmation=False)]
        if has_cart and has_add and request.current_selection:
            return [
                AdvisorAction(
                    type="add_current_routine_to_cart",
                    skus=[item.sku for item in request.current_selection[:8]],
                    reason="добавить текущий набор в корзину",
                    requires_confirmation=False,
                )
            ]
        if has_clear and has_selection and not has_cart:
            return [AdvisorAction(type="clear_selection", reason="очистить текущую подборку", requires_confirmation=True)]
        return []

    async def respond(self, request: AdvisorRequest) -> AdvisorResponse:
        beauty_id = request.beauty_id or BeautyID(consent=True)
        if is_medical_intent(request.message):
            return _medical_refusal(self.name)
        self._ensure_configured()
        allowed_products = self._catalog_subset(request, beauty_id)
        if not allowed_products:
            raise ProviderUnavailable("advisor_catalog_empty", "Advisor cannot run without a configured product catalog.", fallback_allowed=settings.is_non_production)
        parsed: LLMAdvisorPayload | None = None
        last_error: ProviderUnavailable | None = None
        for response_format in self._response_format_ladder():
            payload = self._request_payload(request, beauty_id, allowed_products, response_format)
            logger.info(
                "advisor_provider_request",
                extra={
                    "provider": self.name,
                    "prompt_version": settings.advisor_prompt_version,
                    "allowed_product_count": len(allowed_products),
                    "response_format": response_format,
                },
            )
            try:
                response = await self._send_to_openrouter(payload)
                content = self._content_from_response(response)
                parsed = self._parse_llm_json(content)
                break
            except ProviderUnavailable as exc:
                last_error = exc
                if exc.code in {
                    "advisor_provider_response_format_error",
                    "advisor_provider_invalid_response",
                    "advisor_provider_invalid_json",
                    "advisor_provider_invalid_schema",
                } and response_format != self._response_format_ladder()[-1]:
                    logger.warning(
                        "advisor_openrouter_format_retry",
                        extra={"provider": self.name, "prompt_version": settings.advisor_prompt_version, "code": exc.code, "response_format": response_format},
                    )
                    continue
                raise
        if parsed is None:
            raise last_error or ProviderUnavailable("advisor_provider_invalid_response", "OpenRouter advisor did not return a valid structured response.", fallback_allowed=True)
        grounded = self._recommendations_from_skus(parsed.recommended_skus, allowed_products, beauty_id)
        if parsed.recommended_skus and not grounded:
            raise ProviderUnavailable("advisor_provider_ungrounded_skus", "OpenRouter returned no catalog-grounded SKUs.", fallback_allowed=True)
        if not grounded:
            grounded = allowed_products[: min(4, len(allowed_products))]
        answer = parsed.message.strip()
        if not answer:
            raise ProviderUnavailable("advisor_provider_empty_answer", "OpenRouter advisor returned an empty message.", fallback_allowed=True)
        if contains_internal_prompt_marker(answer):
            raise ProviderUnavailable("advisor_provider_internal_prompt_leak", "OpenRouter advisor response contained internal prompt text.", fallback_allowed=True)
        actions = self._safe_actions(parsed.actions, allowed_products, request)
        has_executable_destination_action = any(
            action.type
            in {
                "add_products_to_cart",
                "add_selection_to_cart",
                "add_current_routine_to_cart",
                "move_selection_to_cart",
                "remove_products_from_cart",
                "clear_cart",
                "add_current_routine_to_shelf",
                "add_product_to_shelf",
                "mark_product_wanted",
                "mark_product_owned",
                "mark_product_buy_later",
                "mark_product_did_not_fit",
            }
            for action in actions
        )
        intent_actions = [] if has_executable_destination_action else self._safe_actions(self._intent_actions(request), allowed_products, request)
        if intent_actions:
            action_keys = {action.id if hasattr(action, "id") else (action.type, tuple(action.skus), action.old_sku, action.new_sku) for action in actions}
            for action in intent_actions:
                key = (action.type, tuple(action.skus), action.old_sku, action.new_sku)
                if key not in action_keys:
                    actions.insert(0, action)
        if not actions and grounded and not parsed.actions:
            actions = [AdvisorAction(type="add_products_to_selection", skus=[item.sku for item in grounded[:6]], reason="добавить к текущей подборке", requires_confirmation=False)]
        return _response_from_recommendations(
            answer=answer,
            recommendations=grounded,
            provider=self.name,
            actions=actions,
            quick_actions=parsed.quick_actions or QUICK_ACTIONS,
            why_this_works=parsed.why_this_works,
            routine_steps=parsed.routine_steps,
            safety_note=parsed.safety_note,
        )


class LLMAdvisorProvider(OpenRouterAdvisorProvider):
    """Backward-compatible alias for the concrete OpenRouter adapter."""


def get_advisor_provider() -> AdvisorProvider:
    if settings.advisor_provider in {"openrouter", "llm"}:
        return OpenRouterAdvisorProvider()
    if settings.is_production:
        return OpenRouterAdvisorProvider()
    return DeterministicAdvisorProvider()


async def build_advisor_response(request: AdvisorRequest) -> AdvisorResponse:
    if is_medical_intent(request.message):
        return _medical_refusal("safety_refusal")
    provider = get_advisor_provider()
    try:
        return await provider.respond(request)
    except ProviderUnavailable as exc:
        logger.warning(
            "advisor_provider_unavailable",
            extra={"provider": getattr(provider, "name", "unknown"), "code": exc.code, "prompt_version": settings.advisor_prompt_version},
        )
        if settings.is_production and not exc.fallback_allowed:
            raise
        fallback = await DeterministicAdvisorProvider().respond(request)
        fallback.provider = f"{getattr(provider, 'name', 'provider')}_fallback:deterministic"
        fallback.fallback_reason = exc.code
        if fallback.safety_note is None and exc.fallback_allowed:
            fallback.safety_note = "advisor_provider_fallback"
        return fallback
