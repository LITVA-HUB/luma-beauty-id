from __future__ import annotations

import asyncio
import json
import logging
import re
from pathlib import Path

import httpx
import pytest

import app.main as main_module
from app.catalog import CATALOG_PATH
from app.config import settings
from app.store import AppStore


@pytest.fixture(autouse=True)
def isolated_store(tmp_path):
    settings.app_env = "development"
    settings.allow_dev_auth = True
    settings.auth_provider = "local"
    settings.catalog_provider = "local"
    settings.checkout_provider = "development_handoff"
    settings.scan_provider = "dev"
    settings.advisor_provider = "deterministic"
    settings.auth_provider_url = ""
    settings.auth_provider_api_key = ""
    settings.catalog_api_base_url = ""
    settings.catalog_api_token = ""
    settings.checkout_handoff_url = ""
    settings.checkout_api_key = ""
    settings.scan_provider_url = ""
    settings.scan_provider_api_key = ""
    settings.openrouter_api_key = ""
    settings.openrouter_base_url = "https://openrouter.ai/api/v1"
    settings.openrouter_model = ""
    settings.openrouter_timeout_seconds = 30
    settings.openrouter_max_retries = 2
    settings.openrouter_response_format = "json_schema"
    settings.gemini_api_key = ""
    settings.access_token_ttl_minutes = 30
    settings.refresh_token_ttl_days = 30
    settings.max_photo_bytes = 5_000_000
    main_module.store = AppStore(str(tmp_path / "luma_test.sqlite3"))
    yield


def request(method: str, path: str, **kwargs) -> httpx.Response:
    async def run() -> httpx.Response:
        transport = httpx.ASGITransport(app=main_module.app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)
    return asyncio.run(run())


def beauty_id_payload() -> dict:
    return {
        "skin_type": "combination",
        "concerns": ["dryness", "dullness"],
        "sensitivity": "medium",
        "fragrance_sensitivity": "avoid",
        "preferred_finish": ["radiant"],
        "makeup_preferences": ["tone"],
        "budget": "mid",
        "ingredient_exclusions": ["alcohol denat"],
        "routine_complexity": "balanced",
        "style_tags": ["soft luxury"],
        "consent": True,
    }


def dev_headers() -> dict[str, str]:
    response = request("POST", "/v1/auth/dev-login")
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def register_payload(email: str = "client@example.com") -> dict:
    return {"name": "Luma Client", "email": email, "password": "strong-password-123", "consent": True}


def tiny_png() -> bytes:
    return bytes.fromhex("89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000A49444154789C6360000002000100FFFF03000006000557BFAB0000000049454E44AE426082")


def known_skus(include_unavailable: bool = False) -> list[str]:
    response = request("GET", "/v1/catalog/products", params={"include_unavailable": include_unavailable})
    assert response.status_code == 200, response.text
    return [item["sku"] for item in response.json()]


def first_available_sku() -> str:
    skus = known_skus(False)
    assert skus
    return skus[0]


def configure_openrouter_for_test() -> None:
    settings.app_env = "staging"
    settings.advisor_provider = "openrouter"
    settings.openrouter_api_key = "unit-test-redacted-token"
    settings.openrouter_base_url = "https://openrouter.ai/api/v1"
    settings.openrouter_model = "unit-test/model"
    settings.openrouter_timeout_seconds = 1
    settings.openrouter_max_retries = 0


def test_health_ready_and_environment():
    health = request("GET", "/health")
    assert health.status_code == 200
    assert health.json()["settings"]["app_env"] == "development"
    assert health.json()["settings"]["openrouter_configured"] is False
    ready = request("GET", "/ready")
    assert ready.status_code == 200
    assert ready.json()["catalog_items"] > 10
    env = request("GET", "/v1/environment")
    assert env.status_code == 200
    assert env.json()["release_candidate"] is True


def test_storage_layer_keeps_sqlite_aliases_available(tmp_path):
    from app.storage import AppStore as StorageAppStore
    from app.storage import SQLiteAppStore, create_app_store

    assert StorageAppStore is SQLiteAppStore
    explicit = SQLiteAppStore(str(tmp_path / "explicit.sqlite3"))
    assert explicit.stats()["path"].endswith("explicit.sqlite3")
    settings.database_url = ""
    created = create_app_store()
    assert isinstance(created, SQLiteAppStore)


def test_delete_account_cascades_and_revokes_sessions():
    registered = request(
        "POST",
        "/v1/auth/register",
        json={"name": "Delete Me", "phone": "+79991234567", "password": "strong-password-123", "consent": True},
    )
    assert registered.status_code == 200, registered.text
    token = registered.json()["access_token"]
    account_id = registered.json()["account"]["account_id"]
    headers = {"Authorization": f"Bearer {token}"}

    saved = request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    assert saved.status_code == 200, saved.text
    assert main_module.store.get_beauty_id(account_id) is not None

    deleted = request("DELETE", "/v1/account/me", headers=headers)
    assert deleted.status_code == 204, deleted.text

    assert main_module.store.get_account(account_id) is None
    assert main_module.store.get_beauty_id(account_id) is None
    assert request("GET", "/v1/auth/me", headers=headers).status_code == 401

    relogin = request("POST", "/v1/auth/login", json={"phone": "+79991234567", "password": "strong-password-123"})
    assert relogin.status_code == 401


def test_recut_catalog_contract_skus_source_skus_and_images():
    response = request("GET", "/v1/catalog/products", params={"include_unavailable": True})
    assert response.status_code == 200, response.text
    products = response.json()
    assert len(products) == 94

    skus = [item["sku"] for item in products]
    assert len(set(skus)) == 94
    assert skus == [f"LUMA-{index:03d}" for index in range(1, 95)]
    assert all(re.fullmatch(r"LUMA-\d{3}", sku) for sku in skus)

    source_skus = [item.get("source_sku") for item in products]
    assert all(source_skus)
    assert len(set(source_skus)) < len(source_skus), "source_sku duplicates are expected and preserved for reference"

    static_root = CATALOG_PATH.parents[1] / "static" / "assets"
    for item in products:
        assert item.get("image_url"), item["sku"]
        assert item.get("card_image_url") == item["image_url"]
        assert item.get("gallery"), item["sku"]
        assert item["gallery"][0] == item["image_url"]
        assert item["source"] == "synthetic_catalog"
        assert item["asset_source"] == "gpt_image_2_packshot_card_crop"
        for image_path in item["gallery"]:
            assert image_path.startswith("/assets/cards/")
            assert (static_root / image_path.removeprefix("/assets/")).exists(), image_path

    first_asset = products[0]["image_url"]
    asset_response = request("GET", first_asset)
    assert asset_response.status_code == 200
    assert asset_response.headers["content-type"].startswith("image/png")


def test_recut_catalog_product_detail_uses_luma_sku_not_source_sku():
    detail = request("GET", "/v1/catalog/products/LUMA-001")
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["sku"] == "LUMA-001"
    assert body["source_sku"] == "FD-BUD-01"
    assert body["catalog_number"] == 1
    assert body["image_url"] == "/assets/cards/001_FD-BUD-01.png"

    source_lookup = request("GET", "/v1/catalog/products/FD-BUD-01")
    assert source_lookup.status_code == 404

    old_lookup = request("GET", "/v1/catalog/products/CL-BUD-001")
    assert old_lookup.status_code == 404



def test_production_ready_reports_contract_adapters_not_implemented():
    settings.app_env = "production"
    settings.allow_dev_auth = False
    settings.auth_provider = "external"
    settings.auth_provider_url = "https://identity.example"
    settings.auth_provider_api_key = "unit-test-auth-token"
    settings.catalog_provider = "external"
    settings.catalog_api_base_url = "https://catalog.example"
    settings.catalog_api_token = "unit-test-catalog-token"
    settings.checkout_provider = "external"
    settings.checkout_handoff_url = "https://checkout.example"
    settings.checkout_api_key = "unit-test-checkout-token"
    settings.scan_provider = "external"
    settings.scan_provider_url = "https://scan.example"
    settings.scan_provider_api_key = "unit-test-scan-token"
    settings.advisor_provider = "openrouter"
    settings.openrouter_api_key = "unit-test-openrouter-token"
    ready = request("GET", "/ready")
    assert ready.status_code == 200
    body = ready.json()
    assert body["status"] == "not_ready"
    joined = " | ".join(body["errors"])
    assert "auth adapter contract" in joined
    assert "catalog adapter contract" in joined
    assert "checkout adapter contract" in joined
    assert "scan adapter contract" in joined

def test_register_login_refresh_logout_and_protected_routes():
    registered = request("POST", "/v1/auth/register", json=register_payload())
    assert registered.status_code == 200, registered.text
    body = registered.json()
    assert body["access_token"] and body["refresh_token"]

    profile = request("GET", "/v1/profile/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert profile.status_code == 200

    refreshed = request("POST", "/v1/auth/refresh", json={"refresh_token": body["refresh_token"]})
    assert refreshed.status_code == 200, refreshed.text
    assert refreshed.json()["access_token"] != body["access_token"]

    login = request("POST", "/v1/auth/login", json={"email": "client@example.com", "password": "strong-password-123"})
    assert login.status_code == 200
    token = login.json()["access_token"]
    refresh = login.json()["refresh_token"]
    logout = request("POST", "/v1/auth/logout", headers={"Authorization": f"Bearer {token}"}, json={"refresh_token": refresh})
    assert logout.status_code == 200
    after_logout = request("GET", "/v1/profile/me", headers={"Authorization": f"Bearer {token}"})
    assert after_logout.status_code == 401


def test_register_and_login_by_phone_without_password():
    registered = request(
        "POST", "/v1/auth/register", json={"name": "Phone Client", "phone": "+7 (905) 123-45-67", "consent": True}
    )
    assert registered.status_code == 200, registered.text
    account = registered.json()["account"]
    assert account["phone_number"] == "+79051234567"
    assert account["email"] is None
    assert account["is_guest"] is False

    # No password was set, so the number alone authenticates.
    login = request("POST", "/v1/auth/login", json={"phone": "89051234567"})
    assert login.status_code == 200, login.text
    assert login.json()["account"]["account_id"] == account["account_id"]


def test_login_requires_password_for_email_accounts():
    request("POST", "/v1/auth/register", json=register_payload("needs-pass@example.com"))
    missing = request("POST", "/v1/auth/login", json={"email": "needs-pass@example.com"})
    assert missing.status_code == 422


def test_guest_account_and_phone_upgrade():
    guest = request("POST", "/v1/auth/guest")
    assert guest.status_code == 200, guest.text
    guest_body = guest.json()
    assert guest_body["account"]["is_guest"] is True
    assert guest_body["account"]["account_id"].startswith("guest_")

    token = guest_body["access_token"]
    upgraded = request(
        "POST",
        "/v1/auth/link-phone",
        headers={"Authorization": f"Bearer {token}"},
        json={"phone": "+79161112233", "name": "Real Client"},
    )
    assert upgraded.status_code == 200, upgraded.text
    upgraded_account = upgraded.json()["account"]
    assert upgraded_account["is_guest"] is False
    assert upgraded_account["phone_number"] == "+79161112233"
    assert upgraded_account["name"] == "Real Client"
    assert upgraded_account["account_id"] == guest_body["account"]["account_id"]


def test_protected_route_without_token_and_expired_token():
    assert request("GET", "/v1/profile/me").status_code == 401
    settings.access_token_ttl_minutes = -1
    login = request("POST", "/v1/auth/register", json=register_payload("expired@example.com"))
    token = login.json()["access_token"]
    expired = request("GET", "/v1/profile/me", headers={"Authorization": f"Bearer {token}"})
    assert expired.status_code == 401
    assert expired.json()["error"]["code"] == "token_expired"


def test_dev_auth_disabled_in_production():
    settings.app_env = "production"
    settings.allow_dev_auth = False
    response = request("POST", "/v1/auth/dev-login")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "dev_auth_disabled"


def test_production_auth_requires_external_provider():
    settings.app_env = "production"
    settings.allow_dev_auth = False
    settings.auth_provider = "external"
    response = request("POST", "/v1/auth/register", json=register_payload("prod@example.com"))
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "auth_provider_unconfigured"


def test_beauty_id_save_load_and_privacy_profile():
    headers = dev_headers()
    saved = request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    assert saved.status_code == 200, saved.text
    assert saved.json()["completion"] > 0.7
    loaded = request("GET", "/v1/beauty-id", headers=headers)
    assert loaded.status_code == 200
    assert loaded.json()["beauty_id"]["fragrance_sensitivity"] == "avoid"
    profile = request("GET", "/v1/profile/me", headers=headers)
    assert profile.status_code == 200
    assert "medical" in profile.json()["privacy"]["medical_boundary"].lower()


def test_saved_routine_save_load_delete_profile_and_account_scope():
    headers = dev_headers()
    skus = ["LUMA-001", "LUMA-002", "LUMA-001"]
    saved = request("PUT", "/v1/routines/current", headers=headers, json={"skus": skus})
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["skus"] == ["LUMA-001", "LUMA-002"]
    assert [item["sku"] for item in body["products"]] == ["LUMA-001", "LUMA-002"]
    assert body["updated_at"]

    loaded = request("GET", "/v1/routines/current", headers=headers)
    assert loaded.status_code == 200, loaded.text
    assert loaded.json()["skus"] == ["LUMA-001", "LUMA-002"]

    profile = request("GET", "/v1/profile/me", headers=headers)
    assert profile.status_code == 200, profile.text
    assert profile.json()["saved_routines"][0]["skus"] == ["LUMA-001", "LUMA-002"]

    other_login = request("POST", "/v1/auth/register", json=register_payload("routine-other@example.com"))
    assert other_login.status_code == 200, other_login.text
    other_headers = {"Authorization": f"Bearer {other_login.json()['access_token']}"}
    other_loaded = request("GET", "/v1/routines/current", headers=other_headers)
    assert other_loaded.status_code == 200
    assert other_loaded.json()["skus"] == []

    deleted = request("DELETE", "/v1/routines/current", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["skus"] == []
    assert request("GET", "/v1/routines/current", headers=headers).json()["skus"] == []


def test_saved_routine_rejects_unknown_and_source_sku():
    headers = dev_headers()
    unknown = request("PUT", "/v1/routines/current", headers=headers, json={"skus": ["UNKNOWN-SKU"]})
    assert unknown.status_code == 400
    assert unknown.json()["error"]["code"] == "invalid_saved_routine_sku"

    source_sku = request("PUT", "/v1/routines/current", headers=headers, json={"skus": ["FD-BUD-01"]})
    assert source_sku.status_code == 400
    assert source_sku.json()["error"]["code"] == "invalid_saved_routine_sku"


def test_active_selection_save_merge_remove_and_account_scope():
    headers = dev_headers()
    saved = request(
        "PUT",
        "/v1/selection/current",
        headers=headers,
        json={
            "items": [
                {"sku": "LUMA-001", "source": "recommendations", "routine_step": "тон", "reason": "base", "match_score": 82},
                {"sku": "LUMA-001", "source": "advisor"},
                {"sku": "LUMA-002", "source": "manual", "locked": True},
            ]
        },
    )
    assert saved.status_code == 200, saved.text
    body = saved.json()
    assert body["skus"] == ["LUMA-001", "LUMA-002"]
    assert body["count"] == 2
    assert body["total_price"] > 0
    assert body["source_summary"]["recommendations"] == 1
    assert body["items"][0]["product"]["sku"] == "LUMA-001"

    merged = request(
        "PATCH",
        "/v1/selection/current/items",
        headers=headers,
        json={"items": [{"sku": "LUMA-002", "source": "advisor", "reason": "updated"}, {"sku": "LUMA-003", "source": "advisor"}]},
    )
    assert merged.status_code == 200, merged.text
    assert merged.json()["skus"] == ["LUMA-001", "LUMA-002", "LUMA-003"]
    assert merged.json()["added_count"] == 1
    assert merged.json()["already_in_selection_count"] == 1
    assert merged.json()["items"][1]["reason"] == "updated"

    source_sku = request("PATCH", "/v1/selection/current/items", headers=headers, json={"items": [{"sku": "FD-BUD-01", "source": "manual"}]})
    assert source_sku.status_code == 400
    assert source_sku.json()["error"]["code"] == "invalid_active_selection_sku"

    removed = request("DELETE", "/v1/selection/current/items/LUMA-002", headers=headers)
    assert removed.status_code == 200
    assert removed.json()["skus"] == ["LUMA-001", "LUMA-003"]

    other_login = request("POST", "/v1/auth/register", json=register_payload("selection-other@example.com"))
    other_headers = {"Authorization": f"Bearer {other_login.json()['access_token']}"}
    other = request("GET", "/v1/selection/current", headers=other_headers)
    assert other.status_code == 200
    assert other.json()["skus"] == []


def test_new_account_starts_with_empty_selection_cart_routine_and_history():
    first_login = request("POST", "/v1/auth/register", json=register_payload("state-a@example.com"))
    assert first_login.status_code == 200, first_login.text
    first_headers = {"Authorization": f"Bearer {first_login.json()['access_token']}"}

    sku = "LUMA-001"
    saved_selection = request("PUT", "/v1/selection/current", headers=first_headers, json={"items": [{"sku": sku, "source": "manual"}]})
    assert saved_selection.status_code == 200, saved_selection.text
    saved_routine = request("PUT", "/v1/routines/current", headers=first_headers, json={"skus": [sku]})
    assert saved_routine.status_code == 200, saved_routine.text
    cart = request("POST", "/v1/cart/items", headers=first_headers, json={"sku": sku, "quantity": 1})
    assert cart.status_code == 200, cart.text
    advisor = request("POST", "/v1/advisor/message", headers=first_headers, json={"message": "добавь SPF", "current_skus": [sku]})
    assert advisor.status_code == 200, advisor.text

    second_login = request("POST", "/v1/auth/register", json=register_payload("state-b@example.com"))
    assert second_login.status_code == 200, second_login.text
    second_headers = {"Authorization": f"Bearer {second_login.json()['access_token']}"}

    assert request("GET", "/v1/selection/current", headers=second_headers).json()["skus"] == []
    assert request("GET", "/v1/cart", headers=second_headers).json()["items"] == []
    assert request("GET", "/v1/routines/current", headers=second_headers).json()["skus"] == []
    assert request("GET", "/v1/advisor/history", headers=second_headers).json()["messages"] == []


def test_events_endpoint_sanitizes_payload_and_requires_auth():
    unauthenticated = request("POST", "/v1/events", json={"event_name": "advisor_message_sent", "payload": {"message": "secret text"}})
    assert unauthenticated.status_code == 401

    headers = dev_headers()
    created = request(
        "POST",
        "/v1/events",
        headers=headers,
        json={"event_name": "advisor_message_sent", "payload": {"length": "short", "message": "do not store"}, "app_version": "1.0", "build": "1", "platform": "ios"},
    )
    assert created.status_code == 200, created.text
    assert created.json()["id"]


def test_feedback_submit_validation_and_auth():
    unauthenticated = request("POST", "/v1/feedback", json={"rating": 5, "message": "Очень удобно"})
    assert unauthenticated.status_code == 401

    headers = dev_headers()
    created = request(
        "POST",
        "/v1/feedback",
        headers=headers,
        json={"rating": 5, "message": "Очень удобно", "context": "settings", "app_version": "1.0", "build": "1"},
    )
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["id"]
    assert body["message"] == "Спасибо, отзыв сохранён."
    assert body["created_at"]

    invalid = request("POST", "/v1/feedback", headers=headers, json={"rating": 6, "message": "too high"})
    assert invalid.status_code == 422


def test_catalog_list_detail_search_and_unavailable_state():
    products = request("GET", "/v1/catalog/products")
    assert products.status_code == 200
    body = products.json()
    assert body
    first = body[0]
    assert {"sku", "source_sku", "catalog_number", "brand", "name", "price_value", "currency", "availability", "inventory_status", "source", "image_url", "gallery"}.issubset(first.keys())
    assert first["sku"].startswith("LUMA-")
    detail = request("GET", f"/v1/catalog/products/{first['sku']}")
    assert detail.status_code == 200
    searched = request("GET", "/v1/catalog/products", params={"q": first["brand"].split()[0]})
    assert searched.status_code == 200
    unavailable = [item for item in body if not item["availability"] or item["inventory_status"] == "out_of_stock"]
    assert unavailable, "seed catalog must expose one unavailable SKU for UI state QA"


def test_production_catalog_unconfigured_returns_clean_error():
    settings.app_env = "production"
    settings.catalog_provider = "external"
    response = request("GET", "/v1/catalog/products")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "catalog_provider_unconfigured"


def test_recommendations_are_catalog_grounded_and_exclude_unavailable():
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    recs = request("POST", "/v1/recommendations", headers=headers, json={"focus": "сияние", "limit": 12, "filters": {}})
    assert recs.status_code == 200, recs.text
    body = recs.json()
    known = set(known_skus(False))
    returned = {item["sku"] for item in body["products"]}
    assert returned
    assert returned.issubset(known)
    assert all(re.fullmatch(r"LUMA-\d{3}", sku) for sku in returned)
    assert "CL-BUD-001" not in returned
    assert "FD-BUD-01" not in returned


def test_recommendations_preview_is_public_and_catalog_grounded():
    response = request(
        "POST",
        "/v1/recommendations/preview",
        json={"beauty_id": beauty_id_payload(), "focus": "сияние", "limit": 12, "filters": {}},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    known = set(known_skus(False))
    returned = {item["sku"] for item in body["products"]}
    assert returned
    assert returned.issubset(known)
    assert all(re.fullmatch(r"LUMA-\d{3}", sku) for sku in returned)
    assert body["hero"]


def test_advisor_medical_refusal_unknown_sku_guard_and_provider_fallback():
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    medical = request("POST", "/v1/advisor/message", headers=headers, json={"message": "Поставь диагноз дерматит и чем лечить", "current_skus": []})
    assert medical.status_code == 200
    assert medical.json()["safety_note"] == "medical_boundary"
    assert not medical.json()["recommendations"]

    normal = request("POST", "/v1/advisor/message", headers=headers, json={"message": "Нужно больше увлажнения и без отдушек", "current_skus": ["UNKNOWN-SKU"]})
    assert normal.status_code == 200, normal.text
    advisor_skus = {item["sku"] for item in normal.json()["recommendations"]}
    assert advisor_skus.issubset(set(known_skus(False)))
    assert advisor_skus
    assert all(re.fullmatch(r"LUMA-\d{3}", sku) for sku in advisor_skus)
    assert "CL-BUD-001" not in advisor_skus
    assert "FD-BUD-01" not in advisor_skus

    settings.app_env = "staging"
    settings.advisor_provider = "openrouter"
    fallback = request("POST", "/v1/advisor/message", headers=headers, json={"message": "SPF и glow", "current_skus": []})
    assert fallback.status_code == 200
    assert fallback.json()["provider"] == "openrouter_fallback:deterministic"
    assert fallback.json()["fallback_reason"] == "advisor_provider_unconfigured"


def test_advisor_history_persists_messages_and_is_scoped_to_account():
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())

    sent = request("POST", "/v1/advisor/message", headers=headers, json={"message": "Подбери SPF для жирной кожи", "current_skus": []})
    assert sent.status_code == 200, sent.text
    sent_body = sent.json()
    assert sent_body["recommended_skus"]

    history = request("GET", "/v1/advisor/history", headers=headers)
    assert history.status_code == 200, history.text
    messages = history.json()["messages"]
    assert [item["role"] for item in messages] == ["user", "assistant"]
    assert messages[0]["content"] == "Подбери SPF для жирной кожи"
    assert messages[0]["recommended_skus"] == []
    assert messages[1]["content"] == sent_body["answer"]
    assert messages[1]["recommended_skus"] == sent_body["recommended_skus"]
    assert all(re.fullmatch(r"LUMA-\d{3}", sku) for sku in messages[1]["recommended_skus"])

    other_login = request("POST", "/v1/auth/register", json=register_payload("history-other@example.com"))
    assert other_login.status_code == 200, other_login.text
    other_headers = {"Authorization": f"Bearer {other_login.json()['access_token']}"}
    other_history = request("GET", "/v1/advisor/history", headers=other_headers)
    assert other_history.status_code == 200
    assert other_history.json()["messages"] == []


def test_advisor_rejects_internal_prompt_leakage_from_visible_content():
    headers = dev_headers()
    leaked_payload = """
    Контекст предыдущего диалога:
    assistant: Я рядом.

    Новое сообщение пользователя:
    Привет

    Ответь именно на новое сообщение в этом контексте. allowed_products JSON schema You are
    """
    forbidden = [
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
    ]

    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": leaked_payload, "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert all(token not in body["answer"] for token in forbidden)

    history = request("GET", "/v1/advisor/history", headers=headers)
    assert history.status_code == 200, history.text
    messages = history.json()["messages"]
    assert messages[0]["role"] == "user"
    assert messages[0]["content"] == "Привет"
    assert all(token not in item["content"] for item in messages for token in forbidden)


def test_advisor_history_clear_and_medical_refusal_persistence():
    headers = dev_headers()
    medical = request("POST", "/v1/advisor/message", headers=headers, json={"message": "Поставь диагноз акне и назначь лечение", "current_skus": []})
    assert medical.status_code == 200, medical.text
    assert medical.json()["safety_note"] == "medical_boundary"

    history = request("GET", "/v1/advisor/history", headers=headers)
    assert history.status_code == 200
    messages = history.json()["messages"]
    assert len(messages) == 2
    assert messages[1]["safety_note"] == "medical_boundary"
    assert messages[1]["recommended_skus"] == []

    cleared = request("DELETE", "/v1/advisor/history", headers=headers)
    assert cleared.status_code == 200
    assert cleared.json()["messages"] == []
    assert request("GET", "/v1/advisor/history", headers=headers).json()["messages"] == []


def test_advisor_respects_excluded_ingredients():
    headers = dev_headers()
    payload = beauty_id_payload()
    payload["ingredient_exclusions"] = ["panthenol"]
    request("PUT", "/v1/beauty-id", headers=headers, json=payload)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "мягкое очищение", "current_skus": []})
    assert response.status_code == 200
    for item in response.json()["recommendations"]:
        haystack = " ".join([item["name"], item["brand"], *item["ingredients"], *item["tags"], *item.get("warnings", [])]).lower()
        assert "panthenol" not in haystack


def test_openrouter_success_json_response_is_catalog_grounded(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    sku = first_available_sku()
    captured: dict = {}

    async def fake_send(self, payload):
        captured.update(payload)
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Я бы собрала короткую glow-routine из текущего каталога.",
                                "quick_actions": ["дешевле", "без отдушек", "SPF"],
                                "actions": [{"type": "add_products_to_selection", "skus": [sku], "old_sku": None, "new_sku": None, "reason": "добавить SPF", "requires_confirmation": False}],
                                "recommended_skus": [sku],
                                "routine_steps": ["увлажнение", "SPF"],
                                "why_this_works": "Выбор учитывает Beauty ID, финиш и текущий каталог.",
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request(
        "POST",
        "/v1/advisor/message",
        headers=headers,
        json={
            "message": "Нужно сияние и SPF",
            "current_skus": [sku],
            "current_selection": [
                {
                    "sku": sku,
                    "brand": "Luma",
                    "name": "Current SPF",
                    "category": "spf",
                    "product_type": "spf",
                    "price_value": 1200,
                    "currency": "RUB",
                    "routine_step": "SPF",
                }
            ],
            "current_cart": [
                {
                    "sku": sku,
                    "brand": "Luma",
                    "name": "Cart SPF",
                    "category": "spf",
                    "price_value": 1200,
                    "currency": "RUB",
                }
            ],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "openrouter"
    assert body["recommended_skus"] == [sku]
    assert body["actions"][0]["type"] == "add_products_to_selection"
    assert body["actions"][0]["skus"] == [sku]
    assert [item["sku"] for item in body["recommendations"]] == [sku]
    assert body["why_this_works"]
    serialized_payload = json.dumps(captured, ensure_ascii=False).lower()
    assert "unit-test-redacted-token" not in serialized_payload
    assert "base64" not in serialized_payload
    assert "raw photo" not in serialized_payload
    assert "photo_b64" not in serialized_payload
    assert "access_token" not in serialized_payload
    assert "refresh_token" not in serialized_payload
    assert "email" not in serialized_payload
    user_context = json.loads(captured["messages"][1]["content"])
    assert user_context["current_selection"][0]["sku"] == sku
    assert user_context["current_cart"][0]["sku"] == sku
    assert user_context["current_skus"] == [sku]
    selection = request("GET", "/v1/selection/current", headers=headers)
    assert selection.status_code == 200
    assert selection.json()["skus"] == []


def test_advisor_context_does_not_treat_saved_routine_as_current_selection(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    sku = first_available_sku()
    saved = request("PUT", "/v1/routines/current", headers=headers, json={"skus": [sku]})
    assert saved.status_code == 200, saved.text
    captured: dict = {}

    async def fake_send(self, payload):
        captured.update(payload)
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Текущая подборка пока пуста.",
                                "quick_actions": [],
                                "actions": [],
                                "recommended_skus": [],
                                "routine_steps": [],
                                "why_this_works": "Сохранённая рутина не равна активной подборке.",
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "что в текущей подборке?", "current_skus": [], "current_selection": [], "current_cart": []})

    assert response.status_code == 200, response.text
    user_context = json.loads(captured["messages"][1]["content"])
    assert user_context["current_selection"] == []
    assert user_context["current_skus"] == []


def test_openrouter_cart_intents_return_executable_actions(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    sku = first_available_sku()

    async def fake_send(self, payload):
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Сейчас добавлю товар в корзину.",
                                "quick_actions": [],
                                "actions": [
                                    {
                                        "type": "add_products_to_cart",
                                        "skus": [sku],
                                        "old_sku": None,
                                        "new_sku": None,
                                        "reason": "выбранный товар из текущей подборки",
                                        "requires_confirmation": False,
                                    }
                                ],
                                "recommended_skus": [],
                                "routine_steps": [],
                                "why_this_works": "Команда относится к корзине, а не к подборке.",
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request(
        "POST",
        "/v1/advisor/message",
        headers=headers,
        json={
            "message": "добавь это в корзину",
            "current_skus": [sku],
            "current_selection": [
                {
                    "sku": sku,
                    "brand": "Luma",
                    "name": "Selected SPF",
                    "category": "spf",
                    "price_value": 1200,
                    "currency": "RUB",
                    "routine_step": "SPF",
                }
            ],
            "current_cart": [],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["actions"][0]["type"] == "add_products_to_cart"
    assert body["actions"][0]["skus"] == [sku]
    assert body["actions"][0]["requires_confirmation"] is False
    assert "добавил" not in body["answer"].lower()
    assert request("GET", "/v1/cart", headers=headers).json()["items"] == []


def test_openrouter_clear_cart_action_is_valid_but_not_applied_by_advisor_endpoint(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    sku = first_available_sku()
    added = request("POST", "/v1/cart/items", headers=headers, json={"sku": sku, "quantity": 1})
    assert added.status_code == 200, added.text

    async def fake_send(self, payload):
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Сейчас очищу корзину.",
                                "quick_actions": [],
                                "actions": [
                                    {
                                        "type": "clear_cart",
                                        "skus": [],
                                        "old_sku": None,
                                        "new_sku": None,
                                        "reason": "явная команда пользователя",
                                        "requires_confirmation": False,
                                    }
                                ],
                                "recommended_skus": [],
                                "routine_steps": [],
                                "why_this_works": "Корзина очищается отдельным действием приложения.",
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "очисти корзину", "current_skus": [], "current_cart": [{"sku": sku, "brand": "Luma", "name": "Cart item", "category": "spf", "price_value": 1200, "currency": "RUB"}]})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["actions"][0]["type"] == "clear_cart"
    assert body["actions"][0]["requires_confirmation"] is False
    assert request("GET", "/v1/cart", headers=headers).json()["total_items"] == 1


def test_openrouter_shelf_intent_is_not_mapped_to_cart(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    sku = first_available_sku()

    async def fake_send(self, payload):
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Сохраню текущую подборку в полку «Хочу попробовать».",
                                "quick_actions": [],
                                "actions": [
                                    {
                                        "type": "add_current_routine_to_shelf",
                                        "skus": [sku],
                                        "old_sku": None,
                                        "new_sku": None,
                                        "reason": "пользователь просит полку, а не корзину",
                                        "requires_confirmation": False,
                                    }
                                ],
                                "recommended_skus": [],
                                "routine_steps": [],
                                "why_this_works": "Полка и корзина остаются разными состояниями.",
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request(
        "POST",
        "/v1/advisor/message",
        headers=headers,
        json={
            "message": "добавь это в полку",
            "current_skus": [sku],
            "current_selection": [
                {
                    "sku": sku,
                    "brand": "Luma",
                    "name": "Selected SPF",
                    "category": "spf",
                    "price_value": 1200,
                    "currency": "RUB",
                }
            ],
            "current_cart": [],
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["actions"][0]["type"] == "add_current_routine_to_shelf"
    assert body["actions"][0]["skus"] == [sku]
    assert request("GET", "/v1/cart", headers=headers).json()["items"] == []


def test_openrouter_action_source_sku_is_rejected(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()

    async def fake_send(self, payload):
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "message": "Сейчас добавлю товар в корзину.",
                                "quick_actions": [],
                                "actions": [
                                    {
                                        "type": "add_products_to_cart",
                                        "skus": ["FD-BUD-01"],
                                        "old_sku": None,
                                        "new_sku": None,
                                        "reason": "source sku должен быть отброшен",
                                        "requires_confirmation": False,
                                    }
                                ],
                                "recommended_skus": [],
                                "routine_steps": [],
                                "why_this_works": None,
                                "safety_note": None,
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "добавь это в корзину", "current_skus": []})
    assert response.status_code == 200, response.text
    assert response.json()["actions"] == []


def test_openrouter_invalid_json_falls_back(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()

    async def fake_send(self, payload):
        return {"choices": [{"message": {"content": "not valid json"}}]}

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "SPF и glow", "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "openrouter_fallback:deterministic"
    assert body["fallback_reason"] == "advisor_provider_invalid_json"
    assert body["recommendations"]


def test_openrouter_unknown_sku_response_is_guarded(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()

    async def fake_send(self, payload):
        return {"choices": [{"message": {"content": json.dumps({"message": "Try this", "quick_actions": [], "recommended_skus": ["UNKNOWN-SKU"], "routine_steps": [], "why_this_works": "", "safety_note": None})}}]}

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "подбери крем", "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "openrouter_fallback:deterministic"
    assert body["fallback_reason"] == "advisor_provider_ungrounded_skus"
    assert {item["sku"] for item in body["recommendations"]}.issubset(set(known_skus(False)))


def test_openrouter_internal_prompt_response_is_blocked(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()
    sku = first_available_sku()

    async def fake_send(self, payload):
        return {"choices": [{"message": {"content": json.dumps({"message": "Контекст предыдущего диалога: You are system prompt", "quick_actions": [], "recommended_skus": [sku], "routine_steps": [], "why_this_works": "", "safety_note": None})}}]}

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "подбери крем", "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "openrouter_fallback:deterministic"
    assert body["fallback_reason"] == "advisor_provider_internal_prompt_leak"
    assert "Контекст предыдущего диалога" not in body["answer"]


def test_openrouter_provider_error_falls_back_without_secret_leak(monkeypatch, caplog):
    from app.advisor import OpenRouterAdvisorProvider
    from app.provider_errors import ProviderUnavailable

    configure_openrouter_for_test()
    secret = settings.openrouter_api_key
    headers = dev_headers()

    async def fake_send(self, payload):
        raise ProviderUnavailable("advisor_provider_timeout", "OpenRouter advisor request failed.", fallback_allowed=True)

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    caplog.set_level(logging.WARNING)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "нужно увлажнение", "current_skus": []})
    assert response.status_code == 200, response.text
    assert secret not in response.text
    assert secret not in caplog.text
    assert "Authorization" not in caplog.text
    assert response.json()["provider"] == "openrouter_fallback:deterministic"
    assert response.json()["fallback_reason"] == "advisor_provider_timeout"


def test_openrouter_medical_request_refuses_without_provider_call(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    headers = dev_headers()

    async def should_not_call(self, payload):
        raise AssertionError("OpenRouter should not be called for medical intent")

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", should_not_call)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "поставь диагноз розацеа и лечение", "current_skus": []})
    assert response.status_code == 200, response.text
    assert response.json()["safety_note"] == "medical_boundary"
    assert response.json()["provider"] == "safety_refusal"
    assert not response.json()["recommendations"]


def test_advisor_dermatitis_treatment_request_refuses_without_network(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider

    configure_openrouter_for_test()
    settings.openrouter_api_key = ""
    headers = dev_headers()

    async def should_not_call(self, payload):
        raise AssertionError("OpenRouter should not be called for medical intent")

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", should_not_call)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "у меня дерматит, чем лечить?", "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "safety_refusal"
    assert body["safety_note"] == "medical_boundary"
    assert body["recommendations"] == []
    assert body["recommended_skus"] == []
    assert body["actions"] == []
    assert "обратиться к специалисту" in body["answer"]
    assert "используйте препарат" not in body["answer"].lower()


def test_openrouter_missing_key_in_production_is_clean_error():
    headers = dev_headers()
    settings.app_env = "production"
    settings.advisor_provider = "openrouter"
    settings.openrouter_api_key = ""
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "SPF", "current_skus": []})
    assert response.status_code == 503
    body = response.json()
    assert body["error"]["code"] == "advisor_provider_unconfigured"
    assert "OPENROUTER_API_KEY" in body["error"]["message"]


def test_cart_add_update_delete_and_unavailable_product():
    headers = dev_headers()
    sku = "LUMA-001"
    cart = request("POST", "/v1/cart/items", headers=headers, json={"sku": sku, "quantity": 2})
    assert cart.status_code == 200, cart.text
    assert cart.json()["total_items"] >= 2
    updated = request("PATCH", f"/v1/cart/items/{sku}", headers=headers, json={"quantity": 1})
    assert updated.status_code == 200
    removed = request("DELETE", f"/v1/cart/items/{sku}", headers=headers)
    assert removed.status_code == 200
    assert request("POST", "/v1/cart/items", headers=headers, json={"sku": "FD-BUD-01", "quantity": 1}).status_code == 404
    assert request("POST", "/v1/cart/items", headers=headers, json={"sku": "CL-BUD-001", "quantity": 1}).status_code == 404
    unavailable = [item for item in request("GET", "/v1/catalog/products").json() if not item["availability"]][0]
    unavailable_cart = request("POST", "/v1/cart/items", headers=headers, json={"sku": unavailable["sku"], "quantity": 1})
    assert unavailable_cart.status_code == 409


def test_cart_persists_after_new_login_session_and_refresh():
    registered = request("POST", "/v1/auth/register", json=register_payload("cart-persist@example.com"))
    assert registered.status_code == 200, registered.text
    first_headers = {"Authorization": f"Bearer {registered.json()['access_token']}"}
    sku = "LUMA-001"

    added = request("POST", "/v1/cart/items", headers=first_headers, json={"sku": sku, "quantity": 2})
    assert added.status_code == 200, added.text
    assert added.json()["items"][0]["sku"] == sku

    login = request("POST", "/v1/auth/login", json={"email": "cart-persist@example.com", "password": "strong-password-123"})
    assert login.status_code == 200, login.text
    second_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    restored = request("GET", "/v1/cart", headers=second_headers)
    assert restored.status_code == 200, restored.text
    assert [(item["sku"], item["quantity"]) for item in restored.json()["items"]] == [(sku, 2)]

    refreshed = request("POST", "/v1/auth/refresh", json={"refresh_token": login.json()["refresh_token"]})
    assert refreshed.status_code == 200, refreshed.text
    refresh_headers = {"Authorization": f"Bearer {refreshed.json()['access_token']}"}
    after_refresh = request("GET", "/v1/cart", headers=refresh_headers)
    assert after_refresh.status_code == 200
    assert [(item["sku"], item["quantity"]) for item in after_refresh.json()["items"]] == [(sku, 2)]


def test_checkout_mode_behavior():
    headers = dev_headers()
    recs = request("POST", "/v1/recommendations", headers=headers, json={"limit": 1, "filters": {}}).json()
    request("POST", "/v1/cart/items", headers=headers, json={"sku": recs["products"][0]["sku"], "quantity": 1})
    handoff = request("POST", "/v1/checkout/handoff", headers=headers, json={})
    assert handoff.status_code == 200
    assert handoff.json()["status"] == "development_handoff"

    settings.app_env = "production"
    settings.checkout_provider = "external"
    settings.checkout_handoff_url = ""
    settings.checkout_api_key = ""
    unavailable = request("POST", "/v1/checkout/handoff", headers=headers, json={})
    assert unavailable.status_code == 200
    assert unavailable.json()["status"] == "unavailable"


def test_scan_validation_and_privacy_delete():
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    valid = request("POST", "/v1/photo/scan", headers=headers, data={"source": "library"}, files={"photo": ("tiny.png", tiny_png(), "image/png")})
    assert valid.status_code == 200, valid.text
    assert valid.json()["recommendations"]["products"]

    unsupported = request("POST", "/v1/photo/scan", headers=headers, data={"source": "library"}, files={"photo": ("bad.txt", b"not an image", "text/plain")})
    assert unsupported.status_code == 415
    assert unsupported.json()["error"]["code"] == "unsupported_photo_mime"

    settings.max_photo_bytes = 8
    too_large = request("POST", "/v1/photo/scan", headers=headers, data={"source": "library"}, files={"photo": ("tiny.png", tiny_png(), "image/png")})
    assert too_large.status_code in {413, 415}

    deleted = request("DELETE", f"/v1/photo/scan/{valid.json()['scan_id']}", headers=headers)
    assert deleted.status_code == 200
    assert deleted.json()["status"] == "accepted"


def test_scan_provider_unavailable_in_production():
    headers = dev_headers()
    settings.app_env = "production"
    settings.scan_provider = "external"
    response = request("POST", "/v1/photo/scan", headers=headers, data={"source": "questionnaire"})
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "scan_provider_unconfigured"


def test_privacy_export_and_delete_request():
    headers = dev_headers()
    request("PUT", "/v1/beauty-id", headers=headers, json=beauty_id_payload())
    export = request("POST", "/v1/privacy/export", headers=headers, json={})
    assert export.status_code == 200, export.text
    assert export.json()["beauty_id"]["consent"] is True
    delete = request("POST", "/v1/privacy/delete-request", headers=headers, json={})
    assert delete.status_code == 200
    assert delete.json()["status"] == "accepted"


def test_structured_errors_include_request_id():
    response = request("GET", "/v1/catalog/products/NO-SUCH-SKU", headers={"X-Request-ID": "test-request-id"})
    assert response.status_code == 404
    body = response.json()
    assert body["error"]["code"] == "product_not_found"
    assert body["error"]["request_id"] == "test-request-id"


def test_openrouter_response_format_ladder_recovers(monkeypatch):
    from app.advisor import OpenRouterAdvisorProvider
    from app.provider_errors import ProviderUnavailable

    configure_openrouter_for_test()
    settings.openrouter_response_format = "json_schema"
    headers = dev_headers()
    sku = first_available_sku()
    seen_formats: list[str] = []

    async def fake_send(self, payload):
        response_format = payload.get("response_format", {})
        if response_format.get("type") == "json_schema":
            seen_formats.append("json_schema")
            raise ProviderUnavailable("advisor_provider_response_format_error", "schema not supported", fallback_allowed=True)
        if response_format.get("type") == "json_object":
            seen_formats.append("json_object")
            return {"choices": [{"message": {"content": json.dumps({"message": "Короткая glow-routine готова.", "quick_actions": ["SPF"], "recommended_skus": [sku], "routine_steps": ["SPF"], "why_this_works": "JSON object mode preserved catalog grounding.", "safety_note": None})}}]}
        raise AssertionError("unexpected response format ladder state")

    monkeypatch.setattr(OpenRouterAdvisorProvider, "_send_to_openrouter", fake_send)
    response = request("POST", "/v1/advisor/message", headers=headers, json={"message": "glow SPF", "current_skus": []})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["provider"] == "openrouter"
    assert body["recommended_skus"] == [sku]
    assert seen_formats == ["json_schema", "json_object"]
