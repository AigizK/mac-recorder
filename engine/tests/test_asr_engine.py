"""Tests for ASREngine model-loading fallbacks."""

from unittest.mock import MagicMock, patch

import pytest

from mac_recorder_engine.asr.engine import ASREngine


def test_load_model_retries_with_cpu_on_external_data_init_error():
    engine = ASREngine(language="en")
    engine._vad = object()

    first_error = RuntimeError(
        "Initializer::Initializer ... model_path must not be empty. "
        "Ensure that a path is provided when the model is created or loaded."
    )
    model = MagicMock()
    wrapped = MagicMock()
    model.with_vad.return_value = wrapped

    with patch(
        "mac_recorder_engine.asr.engine.onnx_asr.load_model",
        side_effect=[first_error, model],
    ) as load_model:
        engine._load_model("en", "nemo-parakeet-tdt-0.6b-v3")

    assert load_model.call_count == 2
    assert load_model.call_args_list[0].args == ("nemo-parakeet-tdt-0.6b-v3",)
    assert load_model.call_args_list[0].kwargs == {}
    assert load_model.call_args_list[1].args == ("nemo-parakeet-tdt-0.6b-v3",)
    assert load_model.call_args_list[1].kwargs == {"providers": ["CPUExecutionProvider"]}
    assert engine._models["en"] is wrapped


def test_load_model_raises_immediately_for_other_errors():
    engine = ASREngine(language="en")
    engine._vad = object()

    with patch(
        "mac_recorder_engine.asr.engine.onnx_asr.load_model",
        side_effect=RuntimeError("unexpected failure"),
    ) as load_model, pytest.raises(RuntimeError, match="unexpected failure"):
        engine._load_model("en", "whisper-base")

    assert load_model.call_count == 1


def test_load_model_uses_cpu_provider_when_forced():
    engine = ASREngine(language="ru")
    engine._vad = object()

    model = MagicMock()
    wrapped = MagicMock()
    model.with_vad.return_value = wrapped

    with patch("mac_recorder_engine.asr.engine.onnx_asr.load_model", return_value=model) as load_model:
        engine._load_model("ru", "gigaam-v3-rnnt", force_cpu=True)

    assert load_model.call_count == 1
    assert load_model.call_args.args == ("gigaam-v3-rnnt",)
    assert load_model.call_args.kwargs == {"providers": ["CPUExecutionProvider"]}
    assert "ru" in engine._cpu_only_languages
    assert engine._models["ru"] is wrapped


def test_recognize_retries_on_coreml_runtime_failure():
    engine = ASREngine(language="ru")

    failed_model = MagicMock()
    failed_model.recognize.side_effect = RuntimeError(
        "CoreMLExecutionProvider ... Unable to compute the prediction using a neural network model (error code: -1)."
    )
    engine._models["ru"] = failed_model

    recovered_model = MagicMock()
    seg = MagicMock()
    seg.text = "Привет"
    seg.start = 0.0
    seg.end = 1.2
    recovered_model.recognize.return_value = [seg]

    with patch.object(engine, "_load_model") as reload_model:
        def _do_reload(lang: str, model_name: str, *, force_cpu: bool = False):
            assert lang == "ru"
            assert model_name == "gigaam-v3-rnnt"
            assert force_cpu is True
            engine._cpu_only_languages.add("ru")
            engine._models["ru"] = recovered_model

        reload_model.side_effect = _do_reload
        segments = engine.recognize(audio=MagicMock(), sample_rate=16000, language="ru")

    assert reload_model.call_count == 1
    assert len(segments) == 1
    assert segments[0]["text"] == "Привет"
    assert segments[0]["language"] == "ru"
