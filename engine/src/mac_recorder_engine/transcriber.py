"""Transcribe a WAV file using onnx-asr models."""

from __future__ import annotations

import logging

import numpy as np
import soundfile as sf

from mac_recorder_engine.asr.engine import ASREngine

logger = logging.getLogger(__name__)

MIC_SOURCE = "mic/speak"
SPEAKER_SOURCE = "speaker/speak"


def transcribe(
    audio_path: str,
    language: str = "auto",
    russian_model: str = "gigaam-v3-rnnt",
    english_model: str = "whisper-base",
) -> tuple[list[dict], str]:
    """
    Transcribe a WAV file.

    Returns (segments, full_text) where segments is a list of
    {"start": float, "end": float, "text": str, "language": str, "source": str}.
    """
    logger.info("Loading audio: %s", audio_path)
    audio, sample_rate = sf.read(audio_path, dtype="float32")

    if audio.ndim == 1:
        logger.info("Audio loaded as mono: %.1f seconds", len(audio) / sample_rate)
    else:
        logger.info(
            "Audio loaded as multi-channel: channels=%d, %.1f seconds",
            audio.shape[1],
            len(audio) / sample_rate,
        )

    audio, sample_rate = _resample_to_16k(audio, sample_rate)

    engine = ASREngine(
        russian_model=russian_model,
        english_model=english_model,
        language=language,
    )
    engine.initialize()

    if audio.ndim == 1:
        segments = engine.recognize(audio, sample_rate)
    elif audio.shape[1] == 1:
        segments = engine.recognize(np.squeeze(audio, axis=1), sample_rate)
    else:
        if audio.shape[1] > 2:
            logger.warning("Audio has %d channels; only first two will be used", audio.shape[1])

        mic_audio = audio[:, 0]
        speaker_audio = audio[:, 1]
        mic_segments = _with_source(engine.recognize(mic_audio, sample_rate), MIC_SOURCE)
        speaker_segments = _with_source(engine.recognize(speaker_audio, sample_rate), SPEAKER_SOURCE)
        segments = sorted(
            [*mic_segments, *speaker_segments],
            key=lambda seg: (seg.get("start", 0.0), seg.get("end", 0.0), seg.get("source", "")),
        )

    full_text = " ".join(seg["text"] for seg in segments)

    logger.info("Transcription complete: %d segments", len(segments))
    return segments, full_text


def _resample_to_16k(audio: np.ndarray, sample_rate: int) -> tuple[np.ndarray, int]:
    if sample_rate == 16000:
        return audio, sample_rate

    logger.info("Resampling from %d to 16000 Hz", sample_rate)
    ratio = 16000 / sample_rate
    new_length = int(len(audio) * ratio)
    indices = np.linspace(0, len(audio) - 1, new_length)
    old_indices = np.arange(len(audio))

    if audio.ndim == 1:
        resampled = np.interp(indices, old_indices, audio).astype(np.float32)
    else:
        channels = [
            np.interp(indices, old_indices, audio[:, channel_index])
            for channel_index in range(audio.shape[1])
        ]
        resampled = np.stack(channels, axis=1).astype(np.float32)

    return resampled, 16000


def _with_source(segments: list[dict], source: str) -> list[dict]:
    tagged_segments = []
    for segment in segments:
        tagged_segments.append({**segment, "source": source})
    return tagged_segments
