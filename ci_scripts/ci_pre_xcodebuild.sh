#!/usr/bin/env bash
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"
if [[ "${CI_XCODEBUILD_ACTION:-}" == archive ]]; then
  # AutoResolve and DayKey tests pin Europe/Berlin; Cloud workers use US TZ.
  export TZ=Europe/Berlin
  bash tools/verify.sh
fi
