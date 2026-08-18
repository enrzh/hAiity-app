#!/bin/bash
set -euo pipefail

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || {
    echo "Homebrew is required to install XcodeGen in Xcode Cloud." >&2
    exit 1
  }
  brew install xcodegen
fi

xcodegen generate --spec project.yml
