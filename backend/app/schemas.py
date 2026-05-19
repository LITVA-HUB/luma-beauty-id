from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

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

    @field_validator("email")
    @classmethod
    def email_shape(cls, value: str) -> str:
        email = value.strip().lower()
        if "@" not in email or "." not in email.split("@")[-1]:
            raise ValueError("invalid_email")
        return email


class AuthLoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=160)
    password: str = Field(min_length=1, max_length=128)

    @field_validator("email")
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

    @field_validator("concerns", "makeup_preferences", "ingredient_exclusions", "style_tags", mode="before")
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

    @model_validator(mode="after")
    def default_gallery(self) -> "Product":
        if not self.gallery and self.image_url:
            self.gallery = [self.image_url]
        return self


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


class AdvisorSelectionProduct(BaseModel):
    sku: str
    brand: str | None = None
    name: str | None = None
    category: str | None = None
    product_type: str | None = None
    price_value: int | None = None
    currency: str | None = None
    routine_step: str | None = None


AdvisorActionType = Literal[
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
]


class AdvisorAction(BaseModel):
    type: AdvisorActionType
    skus: list[str] = Field(default_factory=list, max_length=8)
    old_sku: str | None = None
    new_sku: str | None = None
    reason: str | None = Field(default=None, max_length=500)
    requires_confirmation: bool = False
    metadata: dict[str, object] = Field(default_factory=dict)

    @field_validator("skus", mode="before")
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

    @field_validator("old_sku", "new_sku")
    @classmethod
    def clean_optional_sku(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = value.strip().upper()
        return cleaned or None


class AdvisorRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1200)
    beauty_id: BeautyID | None = None
    current_skus: list[str] = Field(default_factory=list)
    current_selection: list[AdvisorSelectionProduct] = Field(default_factory=list, max_length=30)
    current_cart: list[AdvisorSelectionProduct] = Field(default_factory=list, max_length=30)
    conversation_history: list[AdvisorHistoryMessage] = Field(default_factory=list, exclude=True)


class AdvisorResponse(BaseModel):
    answer: str
    messages: list[AdvisorMessage] = Field(default_factory=list)
    quick_actions: list[str] = Field(default_factory=list)
    actions: list[AdvisorAction] = Field(default_factory=list)
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

    @field_validator("skus", mode="before")
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


SelectionSource = Literal["advisor", "recommendations", "manual", "cart", "saved_routine", "scan"]


class ActiveSelectionItemRequest(BaseModel):
    sku: str
    source: SelectionSource = "manual"
    routine_step: str | None = Field(default=None, max_length=120)
    reason: str | None = Field(default=None, max_length=700)
    match_score: int | None = Field(default=None, ge=0, le=100)
    added_at: datetime | None = None
    updated_at: datetime | None = None
    locked: bool = False
    metadata: dict[str, object] = Field(default_factory=dict)

    @field_validator("sku")
    @classmethod
    def clean_sku(cls, value: str) -> str:
        sku = value.strip().upper()
        if not sku:
            raise ValueError("sku_required")
        return sku


class ActiveSelectionItem(BaseModel):
    sku: str
    product: Product
    source: SelectionSource
    routine_step: str | None = None
    reason: str | None = None
    match_score: int | None = Field(default=None, ge=0, le=100)
    added_at: datetime
    updated_at: datetime | None = None
    locked: bool = False
    metadata: dict[str, object] = Field(default_factory=dict)


class ActiveSelectionPutRequest(BaseModel):
    items: list[ActiveSelectionItemRequest] = Field(default_factory=list, max_length=60)


class ActiveSelectionPatchRequest(BaseModel):
    items: list[ActiveSelectionItemRequest] = Field(default_factory=list, max_length=30)


class ActiveSelectionResponse(BaseModel):
    items: list[ActiveSelectionItem] = Field(default_factory=list)
    skus: list[str] = Field(default_factory=list)
    count: int = 0
    total_price: int = 0
    currency: str = "RUB"
    average_match: float | None = None
    updated_at: datetime | None = None
    source_summary: dict[str, int] = Field(default_factory=dict)
    added_count: int = 0
    already_in_selection_count: int = 0


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

    @field_validator("message")
    @classmethod
    def clean_message(cls, value: str) -> str:
        return value.strip()

    @field_validator("context", "app_version", "build")
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


class EventRequest(BaseModel):
    event_name: str = Field(min_length=1, max_length=120)
    payload: dict[str, object] = Field(default_factory=dict)
    app_version: str | None = Field(default=None, max_length=40)
    build: str | None = Field(default=None, max_length=40)
    platform: str | None = Field(default=None, max_length=40)

    @field_validator("event_name")
    @classmethod
    def clean_event_name(cls, value: str) -> str:
        return value.strip().lower()


class EventResponse(BaseModel):
    id: str
    created_at: datetime


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
