#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/build-icon.py
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-output-worker
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-au-effect-worker
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-au-instrument-worker
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-output-device-catalog
CIRCLR_MODULE_CACHE_PATH="$PWD/.build/app-release/module-cache" ./scripts/swift-local.sh build -c release --scratch-path .build/app-release --product circlr-audition-worker
python3 scripts/package-app.py .build/app-release/release/circlr
