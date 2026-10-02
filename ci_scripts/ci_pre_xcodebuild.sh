#!/usr/bin/env bash
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"
if [[ "${CI_XCODEBUILD_ACTION:-}" == archive ]]; then
  bash tools/verify.sh
fi
