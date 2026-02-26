#!/bin/bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <engine_dir> <hf_cache_dir>" >&2
  exit 1
fi

ENGINE_DIR="$1"
HF_CACHE_DIR="$2"

log() {
  echo "[bootstrap-engine] $*"
}

status() {
  echo "installer:STATUS:$*"
  log "$*"
}

progress() {
  echo "installer:%$1"
}

find_python() {
  if [[ -n "${PYTHON_BIN:-}" && -x "${PYTHON_BIN:-}" ]]; then
    echo "$PYTHON_BIN"
    return 0
  fi
  for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ ! -d "$ENGINE_DIR" ]]; then
  status "Engine directory not found: $ENGINE_DIR"
  exit 1
fi

if [[ ! -f "$ENGINE_DIR/pyproject.toml" ]]; then
  status "Missing pyproject.toml in engine directory: $ENGINE_DIR"
  exit 1
fi

PYTHON="$(find_python || true)"
if [[ -z "$PYTHON" ]]; then
  status "python3 not found on system"
  exit 1
fi

mkdir -p "$HF_CACHE_DIR"

VENV_DIR="$ENGINE_DIR/.venv"
status "Using python: $PYTHON"
status "Creating virtual environment"
progress 40
"$PYTHON" -m venv "$VENV_DIR"

VENV_PY="$VENV_DIR/bin/python3"
VENV_PIP="$VENV_DIR/bin/pip"

status "Installing engine dependencies"
progress 55
"$VENV_PY" -m pip install --upgrade pip
"$VENV_PIP" install -e "$ENGINE_DIR"

status "Downloading ASR models (silero, gigaam-v3-rnnt, nemo-parakeet-tdt-0.6b-v3)"
progress 75
HF_HOME="$HF_CACHE_DIR" "$VENV_PY" - <<'PY'
import onnx_asr

onnx_asr.load_vad("silero")
print("[bootstrap-engine] downloaded silero vad", flush=True)
onnx_asr.load_model("gigaam-v3-rnnt", providers=["CPUExecutionProvider"])
print("[bootstrap-engine] downloaded gigaam-v3-rnnt", flush=True)
onnx_asr.load_model("nemo-parakeet-tdt-0.6b-v3", providers=["CPUExecutionProvider"])
print("[bootstrap-engine] downloaded nemo-parakeet-tdt-0.6b-v3", flush=True)
print("[bootstrap-engine] ASR models downloaded", flush=True)
PY

status "Bootstrap completed"
progress 95
