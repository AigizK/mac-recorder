import numpy as np
import pytest


@pytest.fixture
def sample_audio_16k():
    """3 seconds of 440Hz sine wave at 16kHz."""
    sr = 16000
    t = np.linspace(0, 3.0, sr * 3, dtype=np.float32)
    return np.sin(2 * np.pi * 440 * t), sr


@pytest.fixture
def silence_audio_16k():
    """5 seconds of silence at 16kHz."""
    return np.zeros(16000 * 5, dtype=np.float32), 16000


@pytest.fixture
def stereo_audio_16k():
    """2 seconds of stereo audio at 16kHz."""
    sr = 16000
    t = np.linspace(0, 2.0, sr * 2, dtype=np.float32)
    left = np.sin(2 * np.pi * 440 * t)
    right = np.sin(2 * np.pi * 880 * t)
    return np.stack([left, right], axis=1), sr
