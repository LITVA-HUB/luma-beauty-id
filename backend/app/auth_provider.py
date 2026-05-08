from __future__ import annotations

from abc import ABC, abstractmethod

from .config import settings
from .provider_errors import ProviderUnavailable
from .store import AppStore, StoredAccount


class AuthProvider(ABC):
    name: str

    @abstractmethod
    def register(self, store: AppStore, name: str, email: str, password: str) -> StoredAccount:
        raise NotImplementedError

    @abstractmethod
    def login(self, store: AppStore, email: str, password: str) -> StoredAccount | None:
        raise NotImplementedError


class LocalDevAuthProvider(AuthProvider):
    name = "local"

    def register(self, store: AppStore, name: str, email: str, password: str) -> StoredAccount:
        return store.create_account(name, email, password)

    def login(self, store: AppStore, email: str, password: str) -> StoredAccount | None:
        return store.authenticate(email, password)


class ProductionAuthProvider(AuthProvider):
    name = "production_auth_contract"

    def _ensure_configured(self) -> None:
        if not (settings.auth_provider_url and settings.auth_provider_api_key):
            raise ProviderUnavailable(
                "auth_provider_unconfigured",
                "Production auth provider is not configured. Set AUTH_PROVIDER_URL and AUTH_PROVIDER_API_KEY.",
            )

    def register(self, store: AppStore, name: str, email: str, password: str) -> StoredAccount:
        self._ensure_configured()
        raise ProviderUnavailable(
            "auth_provider_adapter_required",
            "Production auth contract is declared, but the external email/phone/social adapter is not connected in this repository.",
        )

    def login(self, store: AppStore, email: str, password: str) -> StoredAccount | None:
        self._ensure_configured()
        raise ProviderUnavailable(
            "auth_provider_adapter_required",
            "Production auth contract is declared, but the external email/phone/social adapter is not connected in this repository.",
        )


def get_auth_provider() -> AuthProvider:
    if settings.is_production or settings.auth_provider == "external":
        return ProductionAuthProvider()
    return LocalDevAuthProvider()
