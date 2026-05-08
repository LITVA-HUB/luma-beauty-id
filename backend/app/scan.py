from __future__ import annotations

import json
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass

from .config import settings
from .provider_errors import ProviderUnavailable
from .recommendations import recommend_products
from .schemas import BeautyID, RecommendationsRequest, ScanResult, ScanStatus


@dataclass(frozen=True)
class UploadedPhoto:
    content: bytes | None
    mime_type: str | None
    source: str


class ScanValidationError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class ScanProvider(ABC):
    name: str

    @abstractmethod
    async def analyze(self, photo: UploadedPhoto, beauty_id: BeautyID) -> ScanResult:
        raise NotImplementedError


class DevScanProvider(ScanProvider):
    name = "dev_cosmetic_context"

    async def analyze(self, photo: UploadedPhoto, beauty_id: BeautyID) -> ScanResult:
        recs = recommend_products(RecommendationsRequest(beauty_id=beauty_id, focus="scan routine", limit=10, filters={}))
        has_photo = bool(photo.content)
        signals: list[str] = []
        if beauty_id.skin_type:
            signals.append(f"предпочтение по типу кожи: {beauty_id.skin_type}")
        if beauty_id.preferred_finish:
            signals.append(f"желательный финиш: {', '.join(beauty_id.preferred_finish[:2])}")
        if beauty_id.fragrance_sensitivity == "avoid":
            signals.append("учесть чувствительность к отдушкам")
        if not signals:
            signals.append("базовая routine по questionnaire")
        limitations = [
            "исходное фото не сохраняется в истории",
            "визуальные подсказки используются только как cosmetic context" if has_photo else "фото пропущено: подбор основан на questionnaire",
        ]
        summary = (
            "Beauty ID уточнён по фото и предпочтениям. Ниже — cosmetic match по текстуре, финишу и бюджету."
            if has_photo
            else "Beauty ID собран без фото: подбор основан на questionnaire и может быть уточнён в advisor."
        )
        return ScanResult(
            scan_id=str(uuid.uuid4()),
            summary=summary,
            signals=signals,
            limitations=limitations,
            statuses=[
                ScanStatus(key="preparing", label="Подготовка", is_done=True),
                ScanStatus(key="uploading", label="Загрузка" if has_photo else "Фото пропущено", is_done=True),
                ScanStatus(key="analyzing", label="Косметический контекст", is_done=True),
                ScanStatus(key="matching", label="Подбор продуктов", is_done=True),
                ScanStatus(key="ready", label="Готово", is_done=True),
            ],
            recommendations=recs,
        )


class ProductionScanProvider(ScanProvider):
    name = "production_scan_contract"

    async def analyze(self, photo: UploadedPhoto, beauty_id: BeautyID) -> ScanResult:
        if not (settings.scan_provider_url and settings.scan_provider_api_key):
            raise ProviderUnavailable("scan_provider_unconfigured", "Production scan provider is not configured. Set SCAN_PROVIDER_URL and SCAN_PROVIDER_API_KEY.")
        raise ProviderUnavailable("scan_provider_adapter_required", "Production scan contract is declared, but the external scan adapter is not connected in this repository.")


def get_scan_provider() -> ScanProvider:
    if settings.is_production or settings.scan_provider == "external":
        return ProductionScanProvider()
    return DevScanProvider()


def parse_beauty_id_json(raw: str | None) -> BeautyID | None:
    if not raw:
        return None
    data = json.loads(raw)
    return BeautyID.parse_obj(data)


def _detect_image_type(content: bytes) -> str | None:
    if content.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if content.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    # HEIC/HEIF are ISO BMFF files. We accept them by declared MIME here and leave
    # deeper validation to the production image provider.
    if b"ftypheic" in content[:32] or b"ftypheif" in content[:32] or b"ftypmif1" in content[:32]:
        return "heif"
    return None


def validate_photo(content: bytes | None, mime_type: str | None) -> None:
    if not content:
        return
    if len(content) > settings.max_photo_bytes:
        raise ScanValidationError("photo_too_large", f"Photo exceeds {settings.max_photo_bytes} bytes.")
    normalized = (mime_type or "").split(";")[0].strip().lower()
    if normalized not in settings.allowed_photo_mime_types:
        raise ScanValidationError("unsupported_photo_mime", "Only JPEG, PNG, HEIC or HEIF photos are accepted.")
    if normalized in {"image/jpeg", "image/png"}:
        detected = _detect_image_type(content)
        if normalized == "image/jpeg" and detected not in {"jpeg"}:
            raise ScanValidationError("unsupported_photo_content", "Uploaded photo content is not a valid JPEG.")
        if normalized == "image/png" and detected != "png":
            raise ScanValidationError("unsupported_photo_content", "Uploaded photo content is not a valid PNG.")
