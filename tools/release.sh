#!/usr/bin/env bash
#
# One command from a clean tree to a build sitting in App Store Connect.
#
#   tools/release.sh            # build, verify, archive, export  (no upload)
#   tools/release.sh --upload   # …and send it to App Store Connect
#
# Every check in here exists because it already went wrong once — in hAiity or
# in its sibling app. In particular the SDK check: an archive built with
# Xcode-beta signs, exports and transfers perfectly, and is then rejected by
# Apple at ingestion with "Unsupported SDK or Xcode version". That round trip
# takes ten minutes to fail. This takes none.
#
# The verification block reads the BUILT bundles, never project.yml. Everything
# it looks for is something the build system can silently get wrong: XcodeGen
# defaults drifting the widget version away from the app, actool injecting only
# the nested icon key, a resource that never made it into the .appex, a DEBUG
# seam that stopped being DEBUG-only.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${OUT:-/tmp/haiity-release}"
PROJECT="Haiity.xcodeproj"
SCHEME="Haiity"
APP_NAME="Haiity"
BUNDLE_ID="com.aiity.haiity"
TEAM_ID="${TEAM_ID:-H8FW6W6K2D}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$OUT/DerivedData}"
UPLOAD=no
[[ "${1:-}" == "--upload" ]] && UPLOAD=yes

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
fail() { printf '\n\033[31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

mkdir -p "$OUT"

# --- 1. toolchain -----------------------------------------------------------
# Apple accepts beta SDKs for building and refuses them for submitting.
say "Toolchain"
DEV="${DEVELOPER_DIR:-$(xcode-select -p)}"
XCODE_APP="${DEV%/Contents/Developer}"
XCODE_VER=$(defaults read "$XCODE_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "    $XCODE_APP  (Xcode $XCODE_VER)"

if [[ "$XCODE_APP" == *beta* ]]; then
  if [[ "$UPLOAD" == yes ]]; then
    fail "refusing to upload from a beta Xcode ($XCODE_APP).
    App Store Connect rejects beta-SDK builds at ingestion, so this would
    fail after the whole archive + upload cycle. This Mac has a release
    Xcode installed — point DEVELOPER_DIR at it and re-run:
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
      tools/release.sh --upload"
  fi
  echo "    NOTE: beta Xcode — fine for building, cannot be uploaded."
fi

# App Store Connect also rejects archives stamped by a beta macOS, even when
# the archive was made with the public Xcode and SDK. Local verification stays
# available; only the irreversible upload path is blocked here.
OS_BUILD=$(sw_vers -buildVersion 2>/dev/null || true)
if [[ "$UPLOAD" == yes && "$OS_BUILD" =~ [a-z]$ ]]; then
  fail "refusing to upload from beta macOS ($OS_BUILD).
    App Store Connect reports this as ITMS-90111: Unsupported SDK or Xcode
    version. Build the release on Xcode Cloud or a Mac running release macOS."
fi
[[ -z "$OS_BUILD" ]] || echo "    macOS build $OS_BUILD"

# --- 2. project -------------------------------------------------------------
# The .xcodeproj is gitignored: project.yml is the only source of truth, and a
# file missing from it is never compiled. Always regenerate before building.
say "Regenerating the project"
command -v xcodegen >/dev/null || fail "xcodegen not installed (brew install xcodegen)"
xcodegen generate >"$OUT/xcodegen.log" 2>&1 || { cat "$OUT/xcodegen.log"; fail "xcodegen failed"; }
ok "$PROJECT regenerated"

# --- 2b. preflight ----------------------------------------------------------
# A fresh Xcode has no iOS platform, which makes every destination ineligible
# (including "Any iOS Device") and surfaces only deep inside the archive.
say "Preflight"
if ! xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null \
     | grep -q 'platform:iOS[,}]'; then
  fail "no usable iOS destination — the iOS platform is probably not installed
    for this Xcode. Fix (no password needed, ~8.5 GB):
      xcodebuild -downloadPlatform iOS"
fi
ok "ios platform"

# --- 3. tests ---------------------------------------------------------------
# Check the COUNT, not the exit code: a test file absent from project.yml does
# not compile, and xcodebuild still exits 0.
say "Build gates"
# v13-Nav-Umbau (Mehr → Menü oben rechts, native TabView): KEIN Test entfiel —
# die reinen ChromeLayout/MorePanel-Rechnungen samt Tests bleiben; nur
# View-Code (MorePanelSurface) wurde gelöscht (Boden damals 748).
# v13-Nacharbeiten: der Malen-Modus wurde auf Nutzerwunsch ENTFERNT — mit ihm
# ehrlich seine 9 Tests (BackfillBrushTests: Pinsel, paintText, Mode). Keine
# überlebende Zusicherung wurde abgeschwächt. Boden: 748 − 9 = 739.
# v23: die Reminder-Einrichtung bringt zwei Zustandsregeln hinzu.
# Navigation/Karten-Umbau: 12 neue Navigations-, Layout- und Interaktionstests.
# Final-Review-Fix: 8 Navigations-/Lifecycle-Vertraege hinzugekommen.
# Create-Cover-Nachpruefung: 5 Request-/Praesentationsvertraege hinzugekommen.
# Boden: 797 + tappbare Vorschau + feste Wischaktionen = 799.
# Build 46 plus combined Habits/Erinnerungen coverage = 1012.
# More hierarchy, notification opt-out, calendar gate, search and reminder UI = 1020.
# Stable owner ID, login/restore state and visual toast hooks = 1029.
# Per-item calendar opt-out coverage: +5 = 1034.
# Vibrant Home Screen widget policy: +2 = 1036.
# GitHub contribution card: +43 = 1079.
# Notification action slots and live category registration: +8 = 1099.
# Home Screen quick actions (candidates, menu build, type resolution): +9 = 1108.
# Main-actor completion contract for the notification delegate: +1 = 1109.
# The complete test target is compiled by the device test invocation below, but
# only the physical-safe subset is executed on the phone. The complete unit
# test gate must run separately on a host/CI destination.
PHYSICAL_MIN_TESTS=20
PHYSICAL_TESTS=(
  -only-testing:HaiityTests/SwipeRevealMechanicsTests
  -only-testing:HaiityTests/ReminderItemTests/testPresentationPolicyUsesCompactRowsOnlyForReminders
  -only-testing:HaiityTests/ProGateTests/testFreeHabitLimitIsThree
  -only-testing:HaiityTests/ProGateTests/testMayAddHabitMatrixWhenLocked
  -only-testing:HaiityTests/ProGateTests/testCurrentEntitlementPolicyRejectsExpiredRevokedAndNonPurchasedTransactions
  -only-testing:HaiityTests/ProGateTests/testSharedEntitlementSnapshotExpiresWithoutTheAppProcess
  -only-testing:HaiityTests/NotificationActionTests/testConfiguredSlotsResolveToThreeUniqueActionsPerHabitKind
  -only-testing:HaiityTests/NotificationActionTests/testNoneSlotsAreNotRegisteredAndResponseIdentifiersAreDistinct
  -only-testing:HaiityTests/NotificationActionTests/testNotificationSlotChoicesExcludeActionsAlreadyAssignedElsewhere
  -only-testing:HaiityTests/NotificationActionTests/testAssigningAnActionClearsItsPreviousSlot
  -only-testing:HaiityTests/NotificationActionTests/testCategoryDefinitionsContainTheConfiguredActionsForEachHabitKind
  -only-testing:HaiityTests/NotificationActionTests/testSchedulePlansReportsEveryFailedAddAndContinues
  -only-testing:HaiityTests/NotificationActionTests/testLegacyResponseIdentifierStillResolvesFromItsOldCategory
  -only-testing:HaiityTests/NotificationActionTests/testAppOpeningActionIsNotDeliveredSynchronously
  -only-testing:HaiityTests/StatsCardPrefsTests/testNewerRemotePreferencesReplaceLocalPreferences
)
# Physical iPhone Air verification is required after export; never fall back to
# a simulator. Override with DEVICE_ID=<physical iPhone UDID>.
DEVICE_ID="${DEVICE_ID:-00008150-000120AC0287801C}"
# --- 3b. GitHub OAuth client ID --------------------------------------------
say "GitHub OAuth client ID"
CLIENT_ID=$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r"GITHUB_CLIENT_ID:\s*(\S+)", text)
print(m.group(1) if m else "")
PY
)
if [[ -z "$CLIENT_ID" || "$CLIENT_ID" == "REPLACE_ME_CLIENT_ID" ]]; then
  fail "GitHub client ID is missing or still REPLACE_ME_CLIENT_ID.
    Register a public OAuth app with Device Flow enabled, then set
    GITHUB_CLIENT_ID in project.yml. No client secret belongs in the repo."
fi
ok "GitHub client ID configured"

# --- 4. archive -------------------------------------------------------------
say "Archiving"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
rm -rf "$ARCHIVE"
xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates \
  >"$OUT/archive.log" 2>&1 || { tail -40 "$OUT/archive.log"; fail "archive failed (full log: $OUT/archive.log)"; }

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[[ -d "$APP" ]] || fail "no $APP_NAME.app in the archive."
# Widget extensions land in PlugIns/ today; do not hard-code that.
EXT=$(find "$APP" -maxdepth 2 -name '*.appex' -print -quit)
[[ -n "$EXT" && -d "$EXT" ]] || fail "no widget extension in the archive — the
    HaiityWidget dependency dropped out of the app target."
ok "archive at $ARCHIVE"

# --- 5. the checks that caught real bugs ------------------------------------
say "Verifying the built bundles"
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Info.plist" 2>/dev/null || echo ""; }

BUILT_CLIENT_ID=$(plist "$APP" GitHubClientID)
[[ -n "$BUILT_CLIENT_ID" && "$BUILT_CLIENT_ID" != "REPLACE_ME_CLIENT_ID" ]] \
  || fail "GitHubClientID is missing or unresolved in the archived app bundle."
[[ "$BUILT_CLIENT_ID" == "$CLIENT_ID" ]] \
  || fail "GitHubClientID differs between project.yml and the archived app bundle."
ok "GitHub client ID resolved in archived app"

# 5a. versions must match EXACTLY, or ingestion returns ITMS-90473.
# XcodeGen writes its own defaults (1.0/1) into any plist that does not declare
# these, which drifts from the app. Reading project.yml does NOT catch it —
# only the built bundle does.
APP_V=$(plist "$APP" CFBundleShortVersionString);  APP_B=$(plist "$APP" CFBundleVersion)
EXT_V=$(plist "$EXT" CFBundleShortVersionString);  EXT_B=$(plist "$EXT" CFBundleVersion)
echo "    app       $APP_V ($APP_B)"
echo "    extension $EXT_V ($EXT_B)"
[[ -n "$APP_V" && -n "$APP_B" ]] || fail "the app bundle has no version keys."
[[ "$APP_V" == "$EXT_V" && "$APP_B" == "$EXT_B" ]] \
  || fail "app and extension versions differ — ITMS-90473 on upload."
ok "app and widget versions match"

# 5b. TOP-LEVEL CFBundleIconName. actool injects only the nested CFBundleIcons
# variant; App Store Connect reads the top-level key and shows a blank build
# icon without it. (Learned the hard way on the sibling app.)
[[ "$(plist "$APP" CFBundleIconName)" == "AppIcon" ]] \
  || fail "CFBundleIconName is missing/wrong at the TOP LEVEL of the app's
    Info.plist. App Store Connect shows a blank icon for the build.
    Fix: info.properties.CFBundleIconName: AppIcon in project.yml."
ok "CFBundleIconName = AppIcon (top level)"

# 5c. …and the icon has to actually be in the compiled catalog.
[[ -f "$APP/Assets.car" ]] || fail "no Assets.car in the app bundle."
# Consume the full assetutil stream. With pipefail, grep -q closes the pipe
# after the first match and assetutil exits with SIGPIPE on larger catalogs.
xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep '"AppIcon"' >/dev/null \
  || fail "AppIcon is not present in Assets.car — the icon set did not compile.
    Check Haiity/Assets.xcassets/AppIcon.appiconset and
    ASSETCATALOG_COMPILER_APPICON_NAME."
ok "AppIcon present in Assets.car"

# 5c-bis. Alternative Icons (eins je Palette). Der Unit-Test prüft den
# DEBUG-Build; hier zählt der archivierte Release-Build, denn actool ist die
# einzige Stelle, die CFBundleAlternateIcons erzeugt — fehlt ein Name in
# ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES, scheitert der Icon-Wechsel
# stillschweigend erst auf dem Gerät.
# [0-9] gehört ins Muster: die Farbton-Icons heißen AppIcon-H000… — mit
# [A-Za-z]* allein fielen sie still aus Zählung UND Assets.car-Prüfung
# (Build 42: Gate meldete 5, das Bundle trug korrekt 17).
ALT_NAMES=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundleAlternateIcons" \
            "$APP/Info.plist" 2>/dev/null | sed -n 's/^ *\(AppIcon-[A-Za-z0-9]*\) = Dict {/\1/p')
[[ -n "$ALT_NAMES" ]] || fail "no CFBundleAlternateIcons in the app Info.plist —
    the palette-matched icons will never appear.
    Fix: ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES in project.yml."
# project.yml ist die Quelle: jedes dort versprochene Icon muss im BUNDLE
# angekommen sein — in beide Richtungen.
WANTED=$(sed -n 's/.*ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "\(.*\)"/\1/p' project.yml | tr ' ' '\n' | sort)
FOUND=$(echo "$ALT_NAMES" | tr ' ' '\n' | sort)
[[ "$WANTED" == "$FOUND" ]] || fail "alternate icons drifted:
    project.yml: $(echo $WANTED)
    bundle:      $(echo $FOUND)"
for alt in $ALT_NAMES; do
  xcrun assetutil --info "$APP/Assets.car" 2>/dev/null | grep "\"$alt\"" >/dev/null \
    || fail "$alt is declared but missing from Assets.car."
done
ok "alternate icons present ($(echo $ALT_NAMES | wc -w | tr -d ' ')): $(echo $ALT_NAMES | tr '\n' ' ')"

# 5d. Localization. In an extension Bundle.main is the .appex, not the app —
# without the catalog IN the .appex every widget string falls back to German.
# The source language (CFBundleDevelopmentRegion) has no .lproj by design.
DEV_REGION=$(plist "$APP" CFBundleDevelopmentRegion)
LANGS=$(/usr/libexec/PlistBuddy -c "Print :CFBundleLocalizations" "$APP/Info.plist" 2>/dev/null \
        | sed -n 's/^ *\([A-Za-z-]*\)$/\1/p' | grep -v '^$' || true)
[[ -n "$LANGS" ]] || fail "CFBundleLocalizations missing from the app Info.plist."
for bundle in "$APP" "$EXT"; do
  label=$([[ "$bundle" == "$APP" ]] && echo app || echo widget)
  missing=""
  n=0
  for lang in $LANGS; do
    [[ "$lang" == "$DEV_REGION" ]] && continue   # source strings live in the binary
    if [[ -d "$bundle/$lang.lproj" ]]; then n=$((n + 1)); else missing="$missing $lang"; fi
  done
  [[ -z "$missing" ]] || fail "the $label bundle is missing .lproj for:$missing
    For the widget this means every string falls back to $DEV_REGION. Fix:
    add Haiity/Localizable.xcstrings to the target's sources in project.yml."
  [[ "$n" -ge 16 ]] || fail "the $label bundle has only $n .lproj, expected >= 16."
  ok "$label carries $n .lproj"
done

# 5e. No debug seams in the Release build.
#
# The app has launch-argument hooks (-screen, -dump-sharecard, -dump-widgets,
# -reload-widgets) behind #if DEBUG. If one escapes the guard it becomes a
# remote-control surface on a shipped build. (-demo-device-code went away with
# the GitHub device flow; do not re-add names that no longer exist — the gate
# would then be testing nothing.)
#
# Three layers, because the obvious one is a FALSE GREEN on its own: Swift
# packs string literals of <= 15 UTF-8 bytes into the instruction stream as
# immediates, so four of these five seams never reach `strings` output in an
# optimised build — present or not. Measured, not assumed: the same literals
# ARE visible in the unoptimised Debug dylib, which is what makes a
# strings-only gate look like it works.
#
#   1. SOURCE  — every seam literal must sit inside an #if DEBUG region.
#                The only decisive layer: it checks the actual property.
#   2. dSYM    — the DEBUG-only functions must not have been compiled in.
#                The shipped binary is stripped; the archive's dSYM is not.
#   3. STRINGS — the literal must not appear in any Mach-O in the bundle.
#                Catches the seams long enough to become real literals.
#
# Every layer carries a positive control, so a gate that stops looking at
# anything fails loudly instead of passing.
SEAMS="-screen -dump-sharecard -dump-widgets -reload-widgets"

# --- layer 1: source ---
SEAMS="$SEAMS" python3 - "$ROOT" <<'PY' || fail "debug seam outside #if DEBUG (see above)."
import os, re, sys, pathlib

SEAMS = os.environ["SEAMS"].split()
root = pathlib.Path(sys.argv[1])

def strip_comments(line, in_block):
    """Drop // and /* */ comments without touching string literals."""
    out, i, in_str = [], 0, False
    while i < len(line):
        if in_block:
            if line.startswith("*/", i):
                in_block, i = False, i + 2
            else:
                i += 1
            continue
        c = line[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < len(line):
                out.append(line[i + 1]); i += 2; continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if line.startswith("//", i):
            break
        if line.startswith("/*", i):
            in_block, i = True, i + 2
            continue
        if c == '"':
            in_str = True
        out.append(c); i += 1
    return "".join(out), in_block

files = sorted(root.glob("Haiity/**/*.swift")) + sorted(root.glob("HaiityWidget/**/*.swift"))
if not files:
    print("FAILED: the source scan found no .swift files — gate is broken.", file=sys.stderr)
    sys.exit(1)

bad, guarded = [], 0
for path in files:
    stack, in_block = [], False
    for n, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line, in_block = strip_comments(raw, in_block)
        s = line.strip()
        if s.startswith("#if"):
            stack.append(bool(re.match(r"#if\s+DEBUG\b", s)))
            continue
        if s.startswith("#elseif"):
            if stack:
                stack[-1] = bool(re.match(r"#elseif\s+DEBUG\b", s))
            continue
        if s.startswith("#else"):
            if stack:
                stack[-1] = False
            continue
        if s.startswith("#endif"):
            if stack:
                stack.pop()
            continue
        hits = [x for x in SEAMS if '"%s"' % x in line]
        if not hits:
            continue
        if any(stack):
            guarded += len(hits)
        else:
            bad.append("    %s:%d  %s" % (path.relative_to(root), n, ", ".join(hits)))

if bad:
    print("FAILED: these debug seams are NOT inside #if DEBUG:", file=sys.stderr)
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
if guarded == 0:
    print("FAILED: no #if DEBUG-guarded occurrence of any seam was found, so this\n"
          "    gate is checking nothing. The hooks were renamed or removed —\n"
          "    update SEAMS in tools/release.sh deliberately.", file=sys.stderr)
    sys.exit(1)
print("    (source: %d guarded seam literals, 0 unguarded)" % guarded)
PY

# --- layer 2: dSYM symbols ---
DEBUG_FUNCS="handleLaunchScreenArgument dumpShareCards dumpWidgets"
SYM_TOTAL=0
for dwarf in "$ARCHIVE"/dSYMs/*.dSYM/Contents/Resources/DWARF/*; do
  [[ -f "$dwarf" ]] || continue
  SYM_TOTAL=$((SYM_TOTAL + $(nm -a "$dwarf" 2>/dev/null | wc -l | tr -d ' ')))
  for fn in $DEBUG_FUNCS; do
    if nm -a "$dwarf" 2>/dev/null | grep -q "$fn"; then
      fail "the DEBUG-only function '$fn' was compiled into the Release build
    ($(basename "$dwarf")). Its #if DEBUG guard is gone."
    fi
  done
done
[[ "$SYM_TOTAL" -gt 500 ]] || fail "the archive's dSYMs carry only $SYM_TOTAL symbols, so the
    symbol gate could not have detected anything. Check DEBUG_INFORMATION_FORMAT
    and that $ARCHIVE/dSYMs is populated."

# --- layer 3: strings in every Mach-O in the bundle ---
MACHO_COUNT=0
while IFS= read -r bin; do
  MACHO_COUNT=$((MACHO_COUNT + 1))
  LINES=$(strings -a "$bin" 2>/dev/null | wc -l | tr -d ' ')
  [[ "$LINES" -gt 100 ]] || fail "strings(1) read only $LINES lines from $(basename "$bin") —
    the scan below would be meaningless."
  for seam in $SEAMS; do
    if strings -a "$bin" 2>/dev/null | grep -qxF -- "$seam"; then
      fail "debug seam '$seam' is present in Release binary $(basename "$bin")."
    fi
  done
done < <(find "$APP" -type f -exec sh -c 'file -b "$1" | grep -q Mach-O && printf "%s\n" "$1"' _ {} \;)
[[ "$MACHO_COUNT" -ge 2 ]] || fail "only $MACHO_COUNT Mach-O binaries found in the bundle —
    expected at least the app and the widget extension."
ok "no debug seams (source + $SYM_TOTAL dSYM symbols + $MACHO_COUNT Mach-O binaries)"

# 5f. Privacy manifest — in EVERY bundle. Apple checks each one (ITMS-91053).
for bundle in "$APP" "$EXT"; do
  label=$([[ "$bundle" == "$APP" ]] && echo app || echo widget)
  [[ -f "$bundle/PrivacyInfo.xcprivacy" ]] \
    || fail "PrivacyInfo.xcprivacy missing from the $label bundle (ITMS-91053).
    Wire Haiity/PrivacyInfo.xcprivacy into that target's sources in project.yml."
  /usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes" \
    "$bundle/PrivacyInfo.xcprivacy" >/dev/null 2>&1 \
    || fail "the $label privacy manifest has no NSPrivacyAccessedAPITypes."
  ok "$label carries PrivacyInfo.xcprivacy"
done

# --- 6. export --------------------------------------------------------------
say "Exporting shipping IPA for App Store Connect"
DEST=export; [[ "$UPLOAD" == yes ]] && DEST=upload
cat >"$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <!-- Off on purpose. Left at its default (true) Xcode rewrites the build
       number during export/upload, so the version the block above just
       verified is not the version that lands in App Store Connect. -->
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PLIST

rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" \
  -allowProvisioningUpdates >"$OUT/export.log" 2>&1 \
  || { tail -40 "$OUT/export.log"; fail "export failed (full log: $OUT/export.log)"; }

IPA=$(find "$OUT/export" -name '*.ipa' -print -quit)
[[ -n "$IPA" ]] || fail "no .ipa produced by export."
EXPORTED_APP_DIR="$OUT/exported-app"
rm -rf "$EXPORTED_APP_DIR"
mkdir -p "$EXPORTED_APP_DIR"
unzip -q "$IPA" -d "$EXPORTED_APP_DIR" \
  || fail "could not inspect exported IPA: $IPA"
EXPORTED_APP="$EXPORTED_APP_DIR/Payload/$APP_NAME.app"
[[ -d "$EXPORTED_APP" ]] || fail "exported IPA has no $APP_NAME.app."
EXPORTED_APP_V=$(plist "$EXPORTED_APP" CFBundleShortVersionString)
EXPORTED_APP_B=$(plist "$EXPORTED_APP" CFBundleVersion)
[[ "$EXPORTED_APP_V" == "$APP_V" && "$EXPORTED_APP_B" == "$APP_B" ]] \
  || fail "exported app version $EXPORTED_APP_V ($EXPORTED_APP_B) differs from archive $APP_V ($APP_B)."
ok "exported app matches archive ($EXPORTED_APP_V/$EXPORTED_APP_B)"

# The App Store Connect export above is the shipping artifact. Its beta
# profile is not necessarily installable on a physical device, so never use
# that IPA for the device smoke check.
if [[ "$UPLOAD" == yes ]]; then
  echo "    device verification is local-only; skipping development smoke export and physical iPhone tests"
else
  say "Exporting separate development smoke build for the physical iPhone"
  cat >"$OUT/DevelopmentExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

  DEV_EXPORT="$OUT/development-export"
  rm -rf "$DEV_EXPORT"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/DevelopmentExportOptions.plist" -exportPath "$DEV_EXPORT" \
    -allowProvisioningUpdates >"$OUT/development-export.log" 2>&1 \
    || { tail -40 "$OUT/development-export.log"; fail "development smoke export failed (full log: $OUT/development-export.log)"; }

  DEV_IPA=$(find "$DEV_EXPORT" -name '*.ipa' -print -quit)
  [[ -n "$DEV_IPA" ]] || fail "no development smoke IPA produced."
  DEV_APP_DIR="$OUT/development-exported-app"
  rm -rf "$DEV_APP_DIR"
  mkdir -p "$DEV_APP_DIR"
  unzip -q "$DEV_IPA" -d "$DEV_APP_DIR" \
    || fail "could not inspect development smoke IPA: $DEV_IPA"
  DEV_APP="$DEV_APP_DIR/Payload/$APP_NAME.app"
  [[ -d "$DEV_APP" ]] || fail "development smoke IPA has no $APP_NAME.app."
  DEV_APP_V=$(plist "$DEV_APP" CFBundleShortVersionString)
  DEV_APP_B=$(plist "$DEV_APP" CFBundleVersion)
  [[ "$DEV_APP_V" == "$APP_V" && "$DEV_APP_B" == "$APP_B" ]] \
    || fail "development smoke app version $DEV_APP_V ($DEV_APP_B) differs from archive $APP_V ($APP_B)."
  ok "development smoke export matches archive ($DEV_APP_V/$DEV_APP_B)"

# --- 7. development smoke build on the approved physical iPhone ------------
  say "Verifying the development smoke export on the physical iPhone"
  DESTINATIONS=$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null || true)
  PHYSICAL_DESTINATION=$(printf '%s\n' "$DESTINATIONS" | grep -E "id:${DEVICE_ID}([,}])" | grep -E 'platform:iOS([,}])' || true)
  if [[ -z "$PHYSICAL_DESTINATION" ]]; then
    if printf '%s\n' "$DESTINATIONS" | grep -E "id:${DEVICE_ID}([,}])" | grep -q 'platform:iOS Simulator'; then
      fail "DEVICE_ID=$DEVICE_ID is a simulator; a physical iPhone is required."
    fi
    fail "physical iPhone $DEVICE_ID is unavailable. Connect and unlock the approved iPhone, then re-run."
  fi
  xcrun devicectl device install app --device "$DEVICE_ID" "$DEV_APP" \
    >"$OUT/device-install.log" 2>&1 \
    || { tail -40 "$OUT/device-install.log"; fail "development smoke export could not be installed on physical iPhone (full log: $OUT/device-install.log)"; }
  DEVICE_APPS="$OUT/device-apps.json"
  xcrun devicectl device info apps --device "$DEVICE_ID" --bundle-id "$BUNDLE_ID" \
    --json-output "$DEVICE_APPS" >"$OUT/device-info.log" 2>&1 \
    || { tail -40 "$OUT/device-info.log"; fail "could not inspect installed development smoke app (full log: $OUT/device-info.log)"; }
  grep -Fq "\"bundleIdentifier\" : \"$BUNDLE_ID\"" "$DEVICE_APPS" \
    || fail "device app inventory did not include $BUNDLE_ID."
  grep -Fq "\"version\" : \"$APP_V\"" "$DEVICE_APPS" \
    || fail "device app version does not match exported version $APP_V."
  grep -Fq "\"bundleVersion\" : \"$APP_B\"" "$DEVICE_APPS" \
    || fail "device app build does not match exported build $APP_B."
  xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID" \
    >"$OUT/device-launch.log" 2>&1 \
    || { tail -40 "$OUT/device-launch.log"; fail "development smoke app could not be launched on physical iPhone (full log: $OUT/device-launch.log)"; }
  ok "development smoke build running on physical iPhone $DEVICE_ID"

  # This is intentionally after export: the phone runtime gate must follow the
  # archive/export gate, while the complete unit-test gate remains host/CI work.
  say "Physical-safe tests"
  TEST_LOG="$OUT/tests.log"
  xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "id=$DEVICE_ID" -testLanguage de -testRegion DE "${PHYSICAL_TESTS[@]}" \
    -skipPackagePluginValidation -skipMacroValidation -allowProvisioningUpdates \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM="$TEAM_ID" \
    >"$TEST_LOG" 2>&1 || { tail -40 "$TEST_LOG"; fail "physical-safe tests failed or the phone became unavailable (full log: $TEST_LOG)"; }
  COUNT=$(grep -oE 'Executed [0-9]+ tests?' "$TEST_LOG" | tail -1 | grep -oE '[0-9]+' || echo 0)
  [[ "$COUNT" -ge "$PHYSICAL_MIN_TESTS" ]] || fail "only $COUNT physical-safe tests ran, expected >= $PHYSICAL_MIN_TESTS."
  ok "executed $COUNT physical-safe tests (floor $PHYSICAL_MIN_TESTS)"
fi

say "Done — $APP_V ($APP_B)"
if [[ "$UPLOAD" == yes ]]; then
  echo "    uploaded; App Store Connect takes 5–30 min to process it."
else
  echo "    shipping IPA: ${IPA:-no .ipa produced}"
  echo "    development smoke export: ${DEV_IPA:-no .ipa produced}"
  echo "    re-run with --upload to send it."
fi
