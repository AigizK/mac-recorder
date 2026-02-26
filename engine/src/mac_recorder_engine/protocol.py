"""JSON protocol for communication between Swift app and Python engine."""

from __future__ import annotations

import json
import sys
from dataclasses import asdict, dataclass


# --- Commands (Swift -> Python) ---


@dataclass
class TranscribeCommand:
    type: str = "transcribe"
    audio_path: str = ""
    language: str = "auto"
    russian_model: str = "gigaam-v3-rnnt"
    english_model: str = "whisper-base"


def parse_command(raw: str) -> TranscribeCommand:
    """Parse a JSON command string into a command dataclass."""
    data = json.loads(raw)
    cmd_type = data.get("type")

    if cmd_type == "transcribe":
        return TranscribeCommand(
            audio_path=data.get("audio_path", ""),
            language=data.get("language", "auto"),
            russian_model=data.get("russian_model", "gigaam-v3-rnnt"),
            english_model=data.get("english_model", "whisper-base"),
        )
    else:
        raise ValueError(f"Unknown command type: {cmd_type}")


# --- Events (Python -> Swift) ---


@dataclass
class StatusEvent:
    state: str
    message: str
    type: str = "status"


@dataclass
class TranscribingEvent:
    message: str
    type: str = "transcribing"


@dataclass
class TranscriptCompleteEvent:
    segments: list[dict]
    full_text: str
    type: str = "transcript_complete"


@dataclass
class ErrorEvent:
    message: str
    type: str = "error"


Event = StatusEvent | TranscribingEvent | TranscriptCompleteEvent | ErrorEvent


def send_event(event: Event) -> None:
    """Send a JSON event to stdout (for Swift to read)."""
    data = asdict(event)
    line = json.dumps(data, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()
