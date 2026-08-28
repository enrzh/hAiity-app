#!/usr/bin/env bash
# Remove only disposable hAiity development state after a release.
# Available simulators are intentionally never touched: other sessions may be
# using them, and deleting them does not reclaim the stale-device storage that
# Xcode leaves behind. `simctl delete unavailable` is the safe inventory pass.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

echo "==> Removing unavailable CoreSimulator devices"
xcrun simctl delete unavailable || true

echo "==> Removing hAiity repository build output"
if [[ -d "$ROOT/build" ]]; then
  find "$ROOT/build" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi

echo "==> Removing hAiity temporary outputs older than one day"
# `-mtime +1` means older than two complete 24-hour periods on macOS.
# Use minutes so the cleanup matches the one-day policy stated above.
find -H /tmp -maxdepth 1 -type d -name 'haiity-*' -mmin +1440 -prune -exec rm -rf {} + 2>/dev/null || true

echo "==> Remaining simulator inventory"
xcrun simctl list devices available
