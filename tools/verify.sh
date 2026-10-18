#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/generate-project.sh
ruby tools/verification_test.rb
verification_output=${VERIFY_OUT:-$(mktemp -d /tmp/haiity-verify.XXXXXX)}
mkdir -p "$verification_output"
if [[ -z "${TEST_DESTINATION:-}" ]]; then
  simulator=$(xcrun simctl list devices available --json | ruby -rjson -e '
    runtimes = JSON.parse(STDIN.read).fetch("devices")
    devices = runtimes.values.flatten
    phone = devices.find { |d| d["name"].start_with?("iPhone") && d["state"] == "Booted" } || devices.find { |d| d["name"].start_with?("iPhone") }
    abort("An available iPhone simulator is required") unless phone
    runtime = runtimes.find { |_, entries| entries.include?(phone) }.first
    STDERR.puts JSON.generate("simulator" => phone.fetch("name"), "udid" => phone.fetch("udid"), "runtime" => runtime)
    puts phone.fetch("udid")')
  TEST_DESTINATION="platform=iOS Simulator,id=$simulator"
fi
source_fingerprint=$(ruby tools/verification.rb fingerprint)
printf 'Verification destination: %s\n' "$TEST_DESTINATION"
ruby -r ./tools/verification -e 'puts JSON.pretty_generate(identity)'
for plan in Unit Smoke; do
  xcodebuild test -project Haiity.xcodeproj -scheme Haiity -testPlan "$plan" \
    -destination "$TEST_DESTINATION" -parallel-testing-enabled NO \
    "$@" \
    -collect-test-diagnostics never \
    -resultBundlePath "$verification_output/$plan.xcresult" 2>&1 | tee "$verification_output/$plan.log" || {
      tail -40 "$verification_output/$plan.log"
      exit 1
    }
done
ruby tools/verification.rb record "$source_fingerprint" "$verification_output/Unit.xcresult" \
  "$verification_output/Smoke.xcresult" >"$verification_output/evidence.json"
printf 'Verification evidence: %s/evidence.json\n' "$verification_output"
