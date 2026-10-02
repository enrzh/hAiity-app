#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
expected=$(tr -d '[:space:]' < .xcodegen-version)
generator=${XCODEGEN_BIN:-xcodegen}
if [[ -x .ci-tools/xcodegen && -z "${XCODEGEN_BIN:-}" ]]; then generator="$PWD/.ci-tools/xcodegen"; fi
actual=$("$generator" --version)
[[ "$actual" == "Version: $expected" ]] || {
  printf 'XcodeGen %s is required; found %s. See docs/development.md.\n' "$expected" "$actual" >&2
  exit 1
}
"$generator" generate --spec project.yml
