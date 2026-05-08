from __future__ import annotations


class ProviderUnavailable(Exception):
    """Raised when an external provider cannot serve the request safely.

    fallback_allowed distinguishes runtime/provider failures from missing
    production configuration. Missing credentials/contracts should not be masked
    in production; transient provider failures may fall back to deterministic,
    catalog-grounded behavior with an explicit provider label.
    """

    def __init__(self, code: str, message: str, status_code: int = 503, fallback_allowed: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.fallback_allowed = fallback_allowed
