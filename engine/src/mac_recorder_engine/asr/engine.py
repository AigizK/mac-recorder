"""ASR engine: model loading and speech recognition via onnx-asr."""

from __future__ import annotations

import logging

import numpy as np
import onnx_asr

logger = logging.getLogger(__name__)

_MODEL_PATH_EMPTY = "model_path must not be empty"
_INITIALIZER_SIGNATURE = "Initializer::Initializer"
_COREML_PROVIDER = "CoreMLExecutionProvider"
_COREML_RUNTIME_ERROR = "Unable to compute the prediction using a neural network model"


def _should_retry_with_cpu(error: Exception) -> bool:
    """Retry with CPU when CoreML/ORT fails to initialize models with external data."""
    message = str(error)
    return _MODEL_PATH_EMPTY in message and _INITIALIZER_SIGNATURE in message


def _is_coreml_runtime_failure(error: Exception) -> bool:
    """Detect CoreML execution failures that should trigger a CPU fallback."""
    message = str(error)
    return _COREML_PROVIDER in message and _COREML_RUNTIME_ERROR in message


class ASREngine:
    """Manages ASR models (GigaAM for Russian, Parakeet for English) and performs recognition."""

    def __init__(
        self,
        russian_model: str = "gigaam-v3-rnnt",
        english_model: str = "whisper-base",
        language: str = "auto",
    ):
        self._russian_model_name = russian_model
        self._english_model_name = english_model
        self._language = language
        self._vad = None
        self._models: dict[str, object] = {}
        self._cpu_only_languages: set[str] = set()

    def initialize(self) -> list[str]:
        """Load VAD and ASR models. Returns list of loaded model names."""
        logger.info("Loading VAD model: silero")
        self._vad = onnx_asr.load_vad("silero")

        loaded = []
        if self._language in ("ru", "auto"):
            self._load_model("ru", self._russian_model_name)
            loaded.append(self._russian_model_name)
        if self._language in ("en", "auto"):
            self._load_model("en", self._english_model_name)
            loaded.append(self._english_model_name)
        return loaded

    def _load_model(self, lang: str, model_name: str, *, force_cpu: bool = False) -> None:
        logger.info("Loading ASR model: %s (lang=%s)", model_name, lang)
        load_kwargs = {"providers": ["CPUExecutionProvider"]} if force_cpu else {}
        try:
            model = onnx_asr.load_model(model_name, **load_kwargs)
        except Exception as error:
            if force_cpu or not _should_retry_with_cpu(error):
                raise

            logger.warning(
                "Model %s failed with default providers (%s). Retrying with CPUExecutionProvider only.",
                model_name,
                error,
            )
            model = onnx_asr.load_model(model_name, providers=["CPUExecutionProvider"])
            self._cpu_only_languages.add(lang)
        else:
            if force_cpu:
                self._cpu_only_languages.add(lang)
            else:
                self._cpu_only_languages.discard(lang)

        model = model.with_vad(self._vad)
        self._models[lang] = model
        provider_mode = "CPUExecutionProvider only" if lang in self._cpu_only_languages else "default providers"
        logger.info("Model %s loaded (%s)", model_name, provider_mode)

    def recognize(
        self,
        audio: np.ndarray,
        sample_rate: int,
        language: str | None = None,
    ) -> list[dict]:
        """
        Recognize speech in audio array.
        Returns list of segments: [{"start": float, "end": float, "text": str, "language": str}]
        """
        lang = language or self._language
        if lang == "auto":
            lang = self._detect_language(audio, sample_rate)

        model = self._models.get(lang)
        if model is None:
            raise ValueError(f"No model loaded for language: {lang}")

        try:
            return self._run_recognition(model, audio, sample_rate, lang)
        except Exception as error:
            if lang in self._cpu_only_languages or not _is_coreml_runtime_failure(error):
                raise

            model_name = self._model_name_for_language(lang)
            logger.warning(
                "Model %s failed during inference with CoreML (%s). Retrying with CPUExecutionProvider only.",
                model_name,
                error,
            )
            self._load_model(lang, model_name, force_cpu=True)
            return self._run_recognition(self._models[lang], audio, sample_rate, lang)

    def set_language(self, language: str) -> None:
        """Change the active language. Loads model if not yet loaded."""
        self._language = language
        if language == "ru" and "ru" not in self._models:
            self._load_model("ru", self._russian_model_name)
        elif language == "en" and "en" not in self._models:
            self._load_model("en", self._english_model_name)
        elif language == "auto":
            if "ru" not in self._models:
                self._load_model("ru", self._russian_model_name)
            if "en" not in self._models:
                self._load_model("en", self._english_model_name)

    def _detect_language(self, audio: np.ndarray, sample_rate: int) -> str:
        """Try both models on a short sample, pick whichever produces more text."""
        sample_frames = min(len(audio), sample_rate * 5)
        sample = audio[:sample_frames]

        best_lang = "en"
        best_len = 0

        for lang, model in self._models.items():
            try:
                text = ""
                for seg in model.recognize(sample, sample_rate=sample_rate):
                    text += seg.text if hasattr(seg, "text") else str(seg)
                if len(text.strip()) > best_len:
                    best_len = len(text.strip())
                    best_lang = lang
            except Exception:
                continue

        logger.info("Auto-detected language: %s", best_lang)
        return best_lang

    def _model_name_for_language(self, lang: str) -> str:
        if lang == "ru":
            return self._russian_model_name
        if lang == "en":
            return self._english_model_name
        raise ValueError(f"Unknown language: {lang}")

    def _run_recognition(self, model: object, audio: np.ndarray, sample_rate: int, lang: str) -> list[dict]:
        segments = []
        for seg in model.recognize(audio, sample_rate=sample_rate):
            text = seg.text if hasattr(seg, "text") else str(seg)
            if not text.strip():
                continue
            segments.append({
                "start": getattr(seg, "start", 0.0),
                "end": getattr(seg, "end", 0.0),
                "text": text.strip(),
                "language": lang,
            })
        return segments
