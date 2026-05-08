from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, validator

SkinType = Literal["dry", "oily", "combination", "normal", "sensitive"]
Budget = Literal["entry", "mid", "premium", "luxury"]
RoutineComplexity = Literal["minimal", "balanced", "extended"]
Finish = Literal["natural", "radiant", "matte", "satin", "glow"]
Sensitivity = Literal["low", "medium", "high"]
FragranceSensitivity = Literal["avoid", "light_ok", "no_preference"]
ProductDomain = Literal["skincare", "makeup"]
InventoryStatus = Literal["in_stock", "low_stock", "out_of_stock", "unknown"]
CheckoutMode = Literal["unavailable", "development_handoff", "live"]


class ErrorPayload(BaseModel):
    code: str
    message: str
    request_id: str | None = None
    details: dict[str, object] | None = None


class ErrorResponse(BaseModel):
    error: ErrorPayload


class AccountPublic(BaseModel):
    account_id: str
    name: str
    email: str
    created_at: datetime


class AuthRegisterRequest(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    email: str = Field(min_length=5, max_length=160)
    password: str = Field(min_length=8, max_length=128)
    consent: bool = True

    @validator("email")
    @classmethod
    def email_shape(cls, value: str) -> str:
        email = value.strip().lower()
        if "@" not in email or "." not in email.split("@")[-1]:
            raise ValueError("invalid_email")
        return email


class AuthLoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=160)
    password: str = Field(min_length=1, max_length=128)

    @validator("email")
    @classmethod
    def email_shape(cls, value: str) -> str:
        return value.strip().lower()


class TokenRefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=256)


class LogoutRequest(BaseModel):
    refresh_token: str | None = Field(default=None, max_length=256)


class AuthSessionResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_at: datetime
    refresh_expires_at: datetime
    account: AccountPublic
    dev_mode: bool = False
    provider: str = "local"


class BeautyID(BaseModel):
    skin_type: SkinType | None = None
    concerns: list[str] = Field(default_factory=list)
    sensitivity: Sensitivity | None = None
    fragrance_sensitivity: FragranceSensitivity | None = None
    preferred_finish: list[Finish] = Field(default_factory=list)
    makeup_preferences: list[str] = Field(default_factory=list)
    budget: Budget = "mid"
    ingredient_exclusions: list[str] = Field(default_factory=list)
    routine_complexity: RoutineComplexity = "balanced"
    style_tags: list[str] = Field(default_factory=list)
    consent: bool = False
    updated_at: datetime | None = None

    @validator("concerns", "makeup_preferences", "ingredient_exclusions", "style_tags", pre=True)
    @classmethod
    def clean_list(cls, value):
        if value is None:
            return []
        result: list[str] = []
        for item in value:
            token = str(item).strip().lower()
            if token and token not in result:
                result.append(token)
        return result


class BeautyIDResponse(BaseModel):
    beauty_id: BeautyID
    completion: float
    tags: list[str] = Field(default_factory=list)
    privacy_note: str = "Beauty ID stores preferences for product matching. It is not a medical profile."


class Product(BaseModel):
    sku: str
    source_sku: str | None = None
    catalog_number: int | None = None
    brand: str
    name: str
    variant: str | None = None
    display_name: str | None = None
    category: str
    domain: ProductDomain
    price_segment: str
    price_value: int
    currency: str = "RUB"
    image_url: str | None = None
    gallery: list[str] = Field(default_factory=list)
    availability: bool = True
    inventory_status: InventoryStatus = "in_stock"
    skin_types: list[str] = Field(default_factory=list)
    concerns: list[str] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    ingredients: list[str] = Field(default_factory=list)
    ingredient_highlights: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    exclusions: list[str] = Field(default_factory=list)
    finishes: list[str] = Field(default_factory=list)
    coverage_levels: list[str] = Field(default_factory=list)
    color_families: list[str] = Field(default_factory=list)
    texture: str | None = None
    rating: float | None = None
    review_count: int | None = None
    source: str = "local_seed"
    asset_source: str | None = None
    card_image_url: str | None = None
    product_type: str | None = None
    category_group: str | None = None
    updated_at: datetime | None = None

    @validator("gallery", pre=True, always=True)
    @classmethod
    def default_gallery(cls, value, values):
        if value:
            return value
        image_url = values.get("image_url")
        return [image_url] if image_url else []


class RecommendationProduct(Product):
    match_score: int = Field(ge=0, le=100)
    reason: str
    routine_step: str
    warnings: list[str] = Field(default_factory=list)
    alternatives: list[str] = Field(default_factory=list)


class RecommendationsRequest(BaseModel):
    beauty_id: BeautyID | None = None
    focus: str | None = None
    limit: int = Field(default=12, ge=1, le=30)
    filters: dict[str, str] = Field(default_factory=dict)


class RecommendationsResponse(BaseModel):
    hero: RecommendationProduct | None = None
    routine: list[RecommendationProduct] = Field(default_factory=list)
    products: list[RecommendationProduct] = Field(default_factory=list)
    explanation: str
    disclaimer: str
    generated_at: datetime
    provider: str = "deterministic"


class ScanStatus(BaseModel):
    key: Literal["preparing", "uploading", "analyzing", "matching", "ready", "failed"]
    label: str
    is_done: bool = False


class ScanResult(BaseModel):
    scan_id: str
    summary: str
    signals: list[str] = Field(default_factory=list)
    limitations: list[str] = Field(default_factory=list)
    statuses: list[ScanStatus]
    recommendations: RecommendationsResponse
    retention_policy: str = "Raw photos are not persisted by this API unless explicit storage is configured."
    deletion_url: str | None = None
    disclaimer: str = "Beauty Scan is a cosmetic preference helper. It does not diagnose skin conditions or replace professional advice."


class AdvisorMessage(BaseModel):
    role: Literal["user", "assistant"]
    text: str
    created_at: datetime


class AdvisorHistoryMessage(BaseModel):
    id: str
    role: Literal["user", "assistant"]
    content: str
    recommended_skus: list[str] = Field(default_factory=list)
    created_at: datetime
    provider: str | None = None
    prompt_version: str | None = None
    safety_note: str | None = None
    fallback_reason: str | None = None


class AdvisorHistoryResponse(BaseModel):
    messages: list[AdvisorHistoryMessage] = Field(default_factory=list)


class AdvisorRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1200)
    beauty_id: BeautyID | None = None
    current_skus: list[str] = Field(default_factory=list)
    conversation_history: list[AdvisorHistoryMessage] = Field(default_factory=list, exclude=True)


class AdvisorResponse(BaseModel):
    answer: str
    messages: list[AdvisorMessage] = Field(default_factory=list)
    quick_actions: list[str] = Field(default_factory=list)
    recommendations: list[RecommendationProduct] = Field(default_factory=list)
    recommended_skus: list[str] = Field(default_factory=list)
    routine_steps: list[str] = Field(default_factory=list)
    why_this_works: str | None = None
    safety_note: str | None = None
    fallback_reason: str | None = None
    prompt_version: str
    provider: str


class CartItem(BaseModel):
    sku: str
    product: Product
    quantity: int = Field(ge=1, le=50)


class CartResponse(BaseModel):
    items: list[CartItem] = Field(default_factory=list)
    total_items: int
    subtotal: int
    currency: str = "RUB"
    checkout_mode: CheckoutMode = "unavailable"


class SavedRoutineRequest(BaseModel):
    skus: list[str] = Field(default_factory=list, max_length=30)

    @validator("skus", pre=True)
    @classmethod
    def clean_skus(cls, value):
        if value is None:
            return []
        seen: set[str] = set()
        cleaned: list[str] = []
        for item in value:
            sku = str(item).strip().upper()
            if sku and sku not in seen:
                seen.add(sku)
                cleaned.append(sku)
        return cleaned


class SavedRoutineResponse(BaseModel):
    skus: list[str] = Field(default_factory=list)
    products: list[Product] = Field(default_factory=list)
    updated_at: datetime | None = None


class AddCartItemRequest(BaseModel):
    sku: str
    quantity: int = Field(default=1, ge=1, le=20)


class UpdateCartItemRequest(BaseModel):
    quantity: int = Field(ge=0, le=50)


class CheckoutResponse(BaseModel):
    status: Literal["unavailable", "ready", "development_handoff"]
    handoff_url: str | None = None
    message: str
    cart: CartResponse


class FeedbackRequest(BaseModel):
    rating: int = Field(ge=1, le=5)
    message: str = Field(min_length=1, max_length=2000)
    context: str | None = Field(default=None, max_length=160)
    app_version: str | None = Field(default=None, max_length=40)
    build: str | None = Field(default=None, max_length=40)

    @validator("message")
    @classmethod
    def clean_message(cls, value: str) -> str:
        return value.strip()

    @validator("context", "app_version", "build")
    @classmethod
    def clean_optional(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip()
        return cleaned or None


class FeedbackResponse(BaseModel):
    id: str
    created_at: datetime
    message: str = "Спасибо, отзыв сохранён."


class ProfileResponse(BaseModel):
    account: AccountPublic
    beauty_id: BeautyIDResponse | None = None
    saved_routines: list[dict[str, object]] = Field(default_factory=list)
    recommendation_history: list[dict[str, object]] = Field(default_factory=list)
    order_history: list[dict[str, object]] = Field(default_factory=list)
    privacy: dict[str, object] = Field(default_factory=dict)


class PrivacyRequestResponse(BaseModel):
    request_id: str
    status: Literal["accepted"] = "accepted"
    message: str


class ExportResponse(BaseModel):
    account: AccountPublic
    beauty_id: BeautyID | None
    cart: CartResponse
    histories: dict[str, list[dict[str, object]]] = Field(default_factory=dict)
    exported_at: datetime


class EnvironmentResponse(BaseModel):
    app_env: str
    mode: dict[str, object]
    release_candidate: bool = True
