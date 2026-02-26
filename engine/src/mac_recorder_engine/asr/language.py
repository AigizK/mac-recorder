"""Language selection state."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class LanguageState:
    """Tracks current language setting."""

    current: str = "auto"  # "ru", "en", or "auto"

    def effective_language(self) -> str | None:
        """Return the language to pass to ASR, or None for auto-detection."""
        if self.current == "auto":
            return None
        return self.current
