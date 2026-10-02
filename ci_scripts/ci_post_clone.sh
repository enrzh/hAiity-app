#!/bin/bash
set -euo pipefail

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"
cd "$ROOT"

version=$(tr -d '[:space:]' < .xcodegen-version)
generator=${XCODEGEN_BIN:-xcodegen}
if [[ -x .ci-tools/xcodegen && -z "${XCODEGEN_BIN:-}" ]]; then generator="$PWD/.ci-tools/xcodegen"; fi
if [[ "$("$generator" --version 2>/dev/null || true)" != "Version: $version" ]]; then
  # The same immutable generator revision on every Cloud worker.
  generator_root=$(mktemp -d /tmp/haiity-xcodegen.XXXXXX)
  git clone --quiet https://github.com/yonaskolb/XcodeGen.git "$generator_root/source"
  git -C "$generator_root/source" checkout --quiet 8445e778451c7e44237b90281bde622d764b0084
  (cd "$generator_root/source" && swift build -c release --product xcodegen)
  mkdir -p .ci-tools
  cp "$generator_root/source/.build/release/xcodegen" .ci-tools/xcodegen
  cp -R "$generator_root/source/.build/release/XcodeGen_XcodeGenKit.bundle" .ci-tools/
  export XCODEGEN_BIN="$PWD/.ci-tools/xcodegen"
fi

bash tools/generate-project.sh
