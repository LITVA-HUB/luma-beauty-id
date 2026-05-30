from __future__ import annotations

import math
import threading
import time
from abc import ABC, abstractmethod
from collections import defaultdict, deque
from dataclasses import dataclass

from fastapi import HTTPException, Request

from .config import settings


@dataclass(frozen=True)
class RateLimit:
    max_requests: int
    window_seconds: int


@dataclass(frozen=True)
class RateLimitDecision:
    allowed: bool
    retry_after: int


class RateLimiter(ABC):
    """Swap-in interface so a Redis-backed limiter can replace the in-memory one."""

    @abstractmethod
    def check(self, key: str, limit: RateLimit) -> RateLimitDecision:
        ...

    @abstractmethod
    def reset(self) -> None:
        ...


class InMemoryRateLimiter(RateLimiter):
    """Sliding-window log limiter. Process-local; fine for a single instance."""

    def __init__(self, *, time_fn=time.monotonic) -> None:
        self._time_fn = time_fn
        self._lock = threading.Lock()
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def check(self, key: str, limit: RateLimit) -> RateLimitDecision:
        now = self._time_fn()
        window_start = now - limit.window_seconds
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= window_start:
                hits.popleft()
            if len(hits) >= limit.max_requests:
                retry_after = max(1, math.ceil(hits[0] + limit.window_seconds - now))
                return RateLimitDecision(allowed=False, retry_after=retry_after)
            hits.append(now)
            return RateLimitDecision(allowed=True, retry_after=0)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


# Per-action limits. Each tuple of (scope-suffix, RateLimit) is checked in order;
# the first one that trips wins and dictates Retry-After.
LIMITS: dict[str, list[tuple[str, RateLimit]]] = {
    "register": [
        ("ip", RateLimit(5, 60)),
        ("phone", RateLimit(3, 3600)),
    ],
    "login": [
        ("ip", RateLimit(10, 60)),
        ("phone", RateLimit(5, 60)),
    ],
    "guest": [
        ("ip", RateLimit(30, 60)),
    ],
    "dev_login": [
        ("ip", RateLimit(30, 60)),
    ],
    "advisor": [
        ("account", RateLimit(30, 60)),
    ],
    "scan": [
        ("account", RateLimit(10, 60)),
    ],
}


rate_limiter: RateLimiter = InMemoryRateLimiter()


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def enforce(
    request: Request,
    action: str,
    *,
    phone: str | None = None,
    account_id: str | None = None,
) -> None:
    if not settings.rate_limit_enabled:
        return
    scopes = LIMITS.get(action)
    if not scopes:
        return
    values = {
        "ip": client_ip(request),
        "phone": phone,
        "account": account_id,
    }
    for suffix, limit in scopes:
        value = values.get(suffix)
        if not value:
            continue
        key = f"{action}:{suffix}:{value}"
        decision = rate_limiter.check(key, limit)
        if not decision.allowed:
            raise HTTPException(
                status_code=429,
                detail="rate_limited",
                headers={"Retry-After": str(decision.retry_after)},
            )
