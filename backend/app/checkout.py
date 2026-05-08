from __future__ import annotations

from abc import ABC, abstractmethod

from .config import settings
from .provider_errors import ProviderUnavailable
from .schemas import CartResponse, CheckoutResponse


class CheckoutProvider(ABC):
    name: str

    @abstractmethod
    def checkout(self, cart: CartResponse) -> CheckoutResponse:
        raise NotImplementedError

    @abstractmethod
    def mode(self) -> str:
        raise NotImplementedError


class DevelopmentCheckoutProvider(CheckoutProvider):
    name = "development_handoff"

    def mode(self) -> str:
        return "development_handoff" if settings.is_non_production else "unavailable"

    def checkout(self, cart: CartResponse) -> CheckoutResponse:
        if settings.is_production:
            return CheckoutResponse(status="unavailable", handoff_url=None, message="Checkout is unavailable: production checkout provider is not configured.", cart=cart)
        return CheckoutResponse(
            status="development_handoff",
            handoff_url=None,
            message="Development checkout handoff accepted. Connect a retail checkout provider before release.",
            cart=cart,
        )


class ProductionCheckoutProvider(CheckoutProvider):
    name = "production_checkout_contract"

    def mode(self) -> str:
        if settings.checkout_handoff_url and settings.checkout_api_key:
            return "live"
        return "unavailable"

    def checkout(self, cart: CartResponse) -> CheckoutResponse:
        if not (settings.checkout_handoff_url and settings.checkout_api_key):
            return CheckoutResponse(status="unavailable", handoff_url=None, message="Checkout is unavailable until CHECKOUT_HANDOFF_URL and CHECKOUT_API_KEY are configured.", cart=cart)
        raise ProviderUnavailable(
            "checkout_provider_adapter_required",
            "Production checkout contract is declared, but the retail checkout adapter implementation is not connected in this repository.",
        )


def get_checkout_provider() -> CheckoutProvider:
    if settings.is_production or settings.checkout_provider == "external":
        return ProductionCheckoutProvider()
    return DevelopmentCheckoutProvider()
