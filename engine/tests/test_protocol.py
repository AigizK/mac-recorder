import json
from dataclasses import asdict

from mac_recorder_engine.protocol import (
    ErrorEvent,
    StatusEvent,
    TranscribeCommand,
    TranscribingEvent,
    TranscriptCompleteEvent,
    parse_command,
)


def test_parse_transcribe_command():
    raw = json.dumps({
        "type": "transcribe",
        "audio_path": "/tmp/test.wav",
        "language": "ru",
        "russian_model": "gigaam-v3-rnnt",
        "english_model": "whisper-base",
    })
    cmd = parse_command(raw)
    assert isinstance(cmd, TranscribeCommand)
    assert cmd.audio_path == "/tmp/test.wav"
    assert cmd.language == "ru"
    assert cmd.russian_model == "gigaam-v3-rnnt"


def test_parse_transcribe_defaults():
    cmd = parse_command('{"type": "transcribe"}')
    assert isinstance(cmd, TranscribeCommand)
    assert cmd.audio_path == ""
    assert cmd.language == "auto"


def test_parse_unknown_command():
    import pytest
    with pytest.raises(ValueError, match="Unknown command type"):
        parse_command('{"type": "unknown"}')


def test_status_event_dict():
    event = StatusEvent(state="ready", message="Engine ready")
    d = asdict(event)
    assert d["type"] == "status"
    assert d["state"] == "ready"
    assert d["message"] == "Engine ready"


def test_transcribing_event_dict():
    event = TranscribingEvent(message="Transcribing...")
    d = asdict(event)
    assert d["type"] == "transcribing"
    assert d["message"] == "Transcribing..."


def test_transcript_complete_event_dict():
    segments = [{"start": 0.0, "end": 1.0, "text": "Hello", "language": "en"}]
    event = TranscriptCompleteEvent(segments=segments, full_text="Hello")
    d = asdict(event)
    assert d["type"] == "transcript_complete"
    assert len(d["segments"]) == 1
    assert d["full_text"] == "Hello"


def test_error_event_dict():
    event = ErrorEvent(message="Something went wrong")
    d = asdict(event)
    assert d["type"] == "error"
    assert d["message"] == "Something went wrong"
