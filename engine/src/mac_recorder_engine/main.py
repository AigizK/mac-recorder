"""Main loop: reads JSON commands from stdin, sends JSON events to stdout."""

from __future__ import annotations

import logging
import sys

from mac_recorder_engine.protocol import (
    ErrorEvent,
    StatusEvent,
    TranscribingEvent,
    TranscriptCompleteEvent,
    TranscribeCommand,
    parse_command,
    send_event,
)
from mac_recorder_engine.transcriber import transcribe

logger = logging.getLogger(__name__)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
    )

    send_event(StatusEvent(state="ready", message="Engine ready"))

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            command = parse_command(line)
        except Exception as e:
            send_event(ErrorEvent(message=f"Invalid command: {e}"))
            continue

        if isinstance(command, TranscribeCommand):
            try:
                send_event(TranscribingEvent(message="Transcribing..."))
                segments, full_text = transcribe(
                    audio_path=command.audio_path,
                    language=command.language,
                    russian_model=command.russian_model,
                    english_model=command.english_model,
                )
                send_event(TranscriptCompleteEvent(
                    segments=segments,
                    full_text=full_text,
                ))
            except Exception as e:
                logger.exception("Transcription failed")
                send_event(ErrorEvent(message=f"Transcription failed: {e}"))

    send_event(StatusEvent(state="exiting", message="Engine shutting down"))
