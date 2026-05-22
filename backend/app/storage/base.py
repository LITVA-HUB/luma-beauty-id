from __future__ import annotations

from typing import Any, Protocol


class AppStorage(Protocol):
    def stats(self) -> dict[str, Any]:
        raise NotImplementedError
