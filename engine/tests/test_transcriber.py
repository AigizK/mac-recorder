"""Tests for the transcriber module (mocked ASR)."""

from unittest.mock import MagicMock, patch

import numpy as np
import soundfile as sf


def test_transcribe_loads_audio(tmp_path):
    """Test that transcribe reads a WAV file and calls ASR."""
    # Create a test WAV file
    audio = np.sin(2 * np.pi * 440 * np.linspace(0, 1, 16000, dtype=np.float32))
    wav_path = tmp_path / "test.wav"
    sf.write(str(wav_path), audio, 16000)

    with patch("mac_recorder_engine.transcriber.ASREngine") as MockEngine:
        mock_instance = MagicMock()
        MockEngine.return_value = mock_instance
        mock_instance.initialize.return_value = ["test-model"]
        mock_instance.recognize.return_value = [
            {"start": 0.0, "end": 1.0, "text": "Hello", "language": "en"}
        ]

        from mac_recorder_engine.transcriber import transcribe

        segments, full_text = transcribe(str(wav_path), language="en")

        assert len(segments) == 1
        assert segments[0]["text"] == "Hello"
        assert full_text == "Hello"
        mock_instance.initialize.assert_called_once()
        mock_instance.recognize.assert_called_once()


def test_transcribe_stereo_to_mono(tmp_path):
    """Test that stereo audio is transcribed per channel with source labels."""
    sr = 16000
    t = np.linspace(0, 1, sr, dtype=np.float32)
    left = np.sin(2 * np.pi * 440 * t)
    right = np.sin(2 * np.pi * 880 * t)
    stereo = np.stack([left, right], axis=1)

    wav_path = tmp_path / "stereo.wav"
    sf.write(str(wav_path), stereo, sr)

    with patch("mac_recorder_engine.transcriber.ASREngine") as MockEngine:
        mock_instance = MagicMock()
        MockEngine.return_value = mock_instance
        mock_instance.initialize.return_value = []
        mock_instance.recognize.side_effect = [
            [{"start": 0.0, "end": 1.0, "text": "Mic", "language": "en"}],
            [{"start": 0.2, "end": 1.2, "text": "Speaker", "language": "en"}],
        ]

        from mac_recorder_engine.transcriber import transcribe

        segments, full_text = transcribe(str(wav_path))

        assert mock_instance.recognize.call_count == 2

        left_call_audio = mock_instance.recognize.call_args_list[0].args[0]
        right_call_audio = mock_instance.recognize.call_args_list[1].args[0]
        assert left_call_audio.ndim == 1
        assert right_call_audio.ndim == 1

        assert len(segments) == 2
        assert segments[0]["source"] == "mic/speak"
        assert segments[1]["source"] == "speaker/speak"
        assert full_text == "Mic Speaker"
