#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p qa/generated
export CIRCLR_QA_OUTPUT="$PWD/qa/generated"
./scripts/swift-local.sh test 2>&1 | tee qa/generated/tests.log
./scripts/build-app.sh 2>&1 | tee qa/generated/build.log
