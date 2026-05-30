from __future__ import annotations

import pytest

from app.config import settings
from app.rate_limit import InMemoryRateLimiter, RateLimit, rate_limiter

from test_api import register_payload, request


class FakeClock:
    def __init__(self, start: float = 1000.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def test_allows_within_limit():
    limiter = InMemoryRateLimiter()
    limit = RateLimit(max_requests=3, window_seconds=60)
    for _ in range(3):
        assert limiter.check("k", limit).allowed


def test_blocks_over_limit_and_reports_retry_after():
    clock = FakeClock()
    limiter = InMemoryRateLimiter(time_fn=clock)
    limit = RateLimit(max_requests=2, window_seconds=60)
    assert limiter.check("k", limit).allowed
    assert limiter.check("k", limit).allowed
    decision = limiter.check("k", limit)
    assert not decision.allowed
    assert decision.retry_after == 60


def test_releases_after_window():
    clock = FakeClock()
    limiter = InMemoryRateLimiter(time_fn=clock)
    limit = RateLimit(max_requests=1, window_seconds=60)
    assert limiter.check("k", limit).allowed
    assert not limiter.check("k", limit).allowed
    clock.advance(61)
    assert limiter.check("k", limit).allowed


def test_independent_keys_do_not_cross():
    limiter = InMemoryRateLimiter()
    limit = RateLimit(max_requests=1, window_seconds=60)
    assert limiter.check("a", limit).allowed
    assert not limiter.check("a", limit).allowed
    assert limiter.check("b", limit).allowed


def test_reset_clears_state():
    limiter = InMemoryRateLimiter()
    limit = RateLimit(max_requests=1, window_seconds=60)
    assert limiter.check("k", limit).allowed
    assert not limiter.check("k", limit).allowed
    limiter.reset()
    assert limiter.check("k", limit).allowed


@pytest.fixture
def rate_limiting_enabled():
    rate_limiter.reset()
    settings.rate_limit_enabled = True
    try:
        yield
    finally:
        settings.rate_limit_enabled = False
        rate_limiter.reset()


def test_register_endpoint_returns_429_with_retry_after(rate_limiting_enabled):
    last = None
    for index in range(6):
        last = request("POST", "/v1/auth/register", json=register_payload(email=f"client{index}@example.com"))
    assert last is not None
    assert last.status_code == 429, last.text
    assert last.json()["error"]["code"] == "rate_limited"
    assert int(last.headers["Retry-After"]) >= 1
