PYTHON := python3.13
VENV := engine/.venv
VENV_BIN := $(VENV)/bin
SWIFT_BUILD_DIR := MacRecorder/.build/debug

.PHONY: build build-python build-swift run clean setup installer

build: build-python build-swift

build-python: $(VENV_BIN)/activate
	$(VENV_BIN)/pip install -e engine[dev] --quiet

$(VENV_BIN)/activate:
	/opt/homebrew/bin/$(PYTHON) -m venv $(VENV)

build-swift:
	cd MacRecorder && swift build

run: build
	$(SWIFT_BUILD_DIR)/MacRecorder

clean:
	rm -rf $(VENV)
	rm -rf MacRecorder/.build

setup: build
	@echo ""
	@echo "=== Setup ==="
	@echo "1. Run: make run"
	@echo "2. Click menu bar icon → Setup Guide"
	@echo "3. Install BlackHole and create Multi-Output Device"
	@echo ""

test:
	$(VENV_BIN)/pytest engine/tests -v

installer:
	chmod +x scripts/build_installer.sh scripts/postinstall scripts/bootstrap_engine.sh
	scripts/build_installer.sh
