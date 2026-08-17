# GitHub Startup Splash And Motivation Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved GitHub-tile startup animation and expose the existing daily motivation as a server-free Live Activity after its scheduled time when the user returns to hAiity.

**Architecture:** Keep the startup animation in a root-level `StartupSplashView` that overlays the existing `ContentView` without changing app boot or GitHub data flow. Keep motivation policy and App Group day markers in a shared pure model, put ActivityKit orchestration behind an injected client/actor, and render the activity in the existing widget extension with a dedicated configuration.

**Tech Stack:** Swift 5.9, SwiftUI, ActivityKit, WidgetKit, App Intents, UserDefaults App Group storage, XCTest, XcodeGen, iOS 17.0 deployment target.

## Global Constraints

- Minimum deployment target remains iOS 17.0; no third-party dependency, backend, push-to-start service, or new notification planner.
- The local motivation notification remains the fallback because a local notification cannot start a Live Activity while the app is suspended.
- The startup animation runs on every launch, has no skip control, and does not wait for GitHub, CloudKit, StoreKit, or any network request.
- The habit page is hidden behind the splash until the final transition frame; the animation uses deterministic local tile levels.
- Motivation is one activity per day, starts only at/after the configured time on app launch/foreground, becomes stale at local midnight, and does not reappear after same-day dismissal.
- German remains the source language; every new visible string must be added to all existing localizations.
- Preserve the existing uncommitted GitHub work. Re-read each target file immediately before editing because other sessions may modify this checkout.
- Never report UI behavior as verified from source inspection; run the app and inspect screenshots or recorded frames.
- Do not upload a release as part of implementation. Build and release verification must stop before archive upload unless separately requested.

---

## File Map

- Create `Haiity/Models/MotivationActivity.swift`: shared ActivityKit attributes, pure schedule decisions, stale-date calculation, and App Group day-marker storage.
- Create `Haiity/Services/MotivationActivityManager.swift`: serialized reconciliation and the production ActivityKit client.
- Create `Haiity/Intents/MotivationActivityIntents.swift`: shared Live Activity dismissal intent and activity-ending control.
- Create `Haiity/Views/StartupSplashView.swift`: deterministic tile field, animation phases, and accessibility-reduced-motion behavior.
- Create `HaiityWidget/MotivationActivity.swift`: Lock Screen and Dynamic Island rendering for the motivation activity.
- Create `HaiityTests/MotivationActivityTests.swift`: pure policy, storage, manager, and source contracts.
- Create `HaiityTests/StartupSplashTests.swift`: phase/tile determinism and app-root contracts.
- Modify `Haiity/HaiityApp.swift`: place the splash above `ContentView` and hide the app until the final frame.
- Modify `Haiity/Views/ContentView.swift`: reconcile the motivation activity after boot, on foreground, and after store changes.
- Modify `HaiityWidget/HaiityWidget.swift`: register the motivation Live Activity in the existing widget bundle.
- Modify `project.yml`: compile shared motivation ActivityKit types/intents into the widget extension and keep both bundles' Live Activity declarations aligned.
- Modify `Haiity/Localizable.xcstrings`: add compact activity controls and accessibility strings in every supported language.
- Modify `tools/release.sh`: raise the minimum test floor to the exact count executed after the new tests are present.

### Task 1: Pure Motivation Activity Policy

**Files:**
- Create: `Haiity/Models/MotivationActivity.swift`
- Create: `HaiityTests/MotivationActivityTests.swift`

**Interfaces:**
- Produces `MotivationActivityAttributes`, `MotivationActivityRequest`, `MotivationActivityDecision`, `MotivationActivityPolicy`, and `MotivationActivityStorage` for later manager and widget tasks.
- Does not call ActivityKit, UserNotifications, Keychain, CloudKit, or SwiftUI from the pure policy/storage portions.

- [ ] **Step 1: Write failing date and marker tests**

Use a fixed Berlin calendar and these stable interfaces:

```swift
private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.locale = Locale(identifier: "de_DE")
    return c
}()

func testBeforeConfiguredTimeWaits() {
    let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
        .addingTimeInterval(7 * 3600 + 59 * 60)
    XCTAssertEqual(
        MotivationActivityPolicy.decision(minutes: 8 * 60,
                                          now: now,
                                          shownDay: nil,
                                          calendar: calendar),
        .waiting)
}

func testAtConfiguredTimeStartsUntilNextMidnight() {
    let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
        .addingTimeInterval(8 * 3600)
    let decision = MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                     now: now,
                                                     shownDay: nil,
                                                     calendar: calendar)
    XCTAssertEqual(decision,
                   .start(dayKey: "2026-08-17",
                          staleDate: DayKey.date(from: "2026-08-18", calendar: calendar)!))
}

func testNilOrInvalidTimeIsDisabled() {
    let now = DayKey.date(from: "2026-08-17", calendar: calendar)!
    XCTAssertEqual(MotivationActivityPolicy.decision(minutes: nil, now: now,
                                                      shownDay: nil, calendar: calendar), .disabled)
    XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 24 * 60, now: now,
                                                      shownDay: nil, calendar: calendar), .disabled)
}

func testShownDayPreventsSameDayRestartButAllowsNextDay() {
    let today = DayKey.date(from: "2026-08-17", calendar: calendar)!
        .addingTimeInterval(9 * 3600)
    XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                      now: today,
                                                      shownDay: "2026-08-17",
                                                      calendar: calendar),
                   .alreadyShown)

    let tomorrow = DayKey.date(from: "2026-08-18", calendar: calendar)!
        .addingTimeInterval(9 * 3600)
    XCTAssertEqual(MotivationActivityPolicy.decision(minutes: 8 * 60,
                                                      now: tomorrow,
                                                      shownDay: "2026-08-17",
                                                      calendar: calendar),
                   .start(dayKey: "2026-08-18",
                          staleDate: DayKey.date(from: "2026-08-19", calendar: calendar)!))
}

func testAppGroupMarkerRoundTripsThroughInjectedDefaults() {
    let suite = "MotivationActivityTests.marker"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
    MotivationActivityStorage.markShown("2026-08-17", in: defaults)
    XCTAssertEqual(MotivationActivityStorage.shownDay(in: defaults), "2026-08-17")
    MotivationActivityStorage.clearShown(in: defaults)
    XCTAssertNil(MotivationActivityStorage.shownDay(in: defaults))
}
```

The test must also assert that `MotivationActivityRequest` preserves the
captured day key, title, body, and stale date without recomputing text.

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:HaiityTests/MotivationActivityTests
```

Expected: FAIL because the new policy types do not exist.

- [ ] **Step 2: Implement the shared attributes, decision, and storage types**

Use these public shapes:

```swift
#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

#if canImport(ActivityKit)
struct MotivationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let displayedAt: Date
    }

    let dayKey: String
    let title: String
    let body: String
}
#endif

struct MotivationActivityRequest: Equatable, Sendable {
    let dayKey: String
    let title: String
    let body: String
    let staleDate: Date
}

enum MotivationActivityDecision: Equatable {
    case disabled
    case waiting
    case alreadyShown
    case start(dayKey: String, staleDate: Date)
}

enum MotivationActivityPolicy {
    static func decision(minutes: Int?, now: Date, shownDay: String?,
                         calendar: Calendar) -> MotivationActivityDecision
    static func scheduledDate(minutes: Int?, dayKey: String,
                              calendar: Calendar) -> Date?
    static func nextMidnight(after date: Date, calendar: Calendar) -> Date
}

enum MotivationActivityStorage {
    static let shownDayKey = "motivationActivityShownDay"
    static func shownDay(in defaults: UserDefaults) -> String?
    static func markShown(_ day: String, in defaults: UserDefaults)
    static func clearShown(in defaults: UserDefaults)
    static func productionDefaults() -> UserDefaults
}
```

`decision` uses `DayKey.key(for:calendar:)`, the configured local hour/minute,
and `fire <= now` to distinguish `.waiting` from `.start`. It computes the
stale date as the next local calendar day, not `now + 24 hours`, so daylight
savings transitions remain correct. `productionDefaults()` uses the existing
App Group suite; tests always inject a named suite and remove it in teardown.

- [ ] **Step 3: Run the pure tests and commit the policy**

Run the focused class again; expected: all policy and storage tests PASS.

```bash
git add Haiity/Models/MotivationActivity.swift \
  HaiityTests/MotivationActivityTests.swift
git commit -m "Add motivation activity scheduling policy"
```

### Task 2: ActivityKit Manager And Dismissal Intent

**Files:**
- Create: `Haiity/Services/MotivationActivityManager.swift`
- Create: `Haiity/Intents/MotivationActivityIntents.swift`
- Modify: `HaiityTests/MotivationActivityTests.swift`

**Interfaces:**
- Consumes `MotivationActivityPolicy`, `MotivationActivityStorage`, and
  `Motivation.message(name:today:)` from Task 1 and existing models.
- Produces an injected `MotivationActivityClient` and the shared
  `MotivationActivityManager.shared` used by `ContentView`.

- [ ] **Step 1: Write failing manager tests with a fake client**

Add a recording client and test the serialized manager behavior without
requesting real ActivityKit activities:

```swift
actor RecordedMotivationActivityClient: MotivationActivityClient {
    enum TestActivityError: Error { case denied }

    private var active: Set<String> = []
    private var starts: [MotivationActivityRequest] = []
    private var ended: [String?] = []
    var shouldThrow = false

    func activeDayKeys() async -> Set<String> { active }
    func start(_ request: MotivationActivityRequest) async throws {
        if shouldThrow { throw TestActivityError.denied }
        starts.append(request)
        active.insert(request.dayKey)
    }
    func end(dayKey: String?) async {
        ended.append(dayKey)
        if let dayKey { active.remove(dayKey) } else { active.removeAll() }
    }
    func snapshot() -> (Set<String>, [MotivationActivityRequest], [String?]) {
        (active, starts, ended)
    }
}
```

The actor's `snapshot()` accessor exposes the recorded arrays to assertions.
Cover these cases:

- before the configured time records no start;
- after the configured time records one request with the exact day message and
  next-midnight stale date;
- a current active day is preserved and a previous-day activity is ended;
- a shown-day marker prevents a second start after dismissal;
- disabling motivation ends all activities and clears the opt-in marker;
- a client error leaves the shown-day marker unset and does not throw through
  the app-facing call;
- two concurrent reconciliations result in one start.

Run the focused tests; expected: FAIL because the client and manager are not
defined.

- [ ] **Step 2: Implement the serialized client boundary and manager**

Define the exact seam:

```swift
protocol MotivationActivityClient: Sendable {
    func activeDayKeys() async -> Set<String>
    func start(_ request: MotivationActivityRequest) async throws
    func end(dayKey: String?) async
}

actor MotivationActivityManager {
    static let shared = MotivationActivityManager(
        client: ActivityKitMotivationActivityClient(),
        defaults: MotivationActivityStorage.productionDefaults())

    init(client: MotivationActivityClient,
         defaults: UserDefaults)

    func reconcile(motivationMinutes: Int?, name: String?,
                   now: Date = .now,
                   calendar: Calendar = .current) async
}
```

`reconcile` reads the policy decision, ends activity keys from previous days,
ends all activity and clears the marker when motivation is disabled, and
returns without work for `.waiting` or `.alreadyShown`. For `.start`, it
builds `Motivation.message(name:today:)`, requests exactly one activity, and
marks the day only after the client accepts the request. The actor is the
single serialization point for foreground/store-change races.

`ActivityKitMotivationActivityClient` must:

- return `Activity<MotivationActivityAttributes>.activities` day keys;
- reject a start when `ActivityAuthorizationInfo().areActivitiesEnabled` is
  false;
- call `Activity.request(attributes:content:pushType: nil)` with the captured
  message and `staleDate`;
- end only the matching motivation activity when a day key is supplied, or
  all motivation activities when it is nil;
- log only an error category and never the title/body or any token.

- [ ] **Step 3: Add the shared dismissal intent**

Implement the following intent in `Haiity/Intents/MotivationActivityIntents.swift`:

```swift
@available(iOS 17.0, *)
struct DismissMotivationActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Ausblenden"
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MotivationActivityControl.endAll()
        return .result()
    }
}

enum MotivationActivityControl {
    static func endAll() async
}
```

The marker is already set on successful creation, so both this intent and
ordinary system swipe dismissal remain dismissed for the day. The control
must iterate only `Activity<MotivationActivityAttributes>.activities` and
must never end a habit-session activity.

- [ ] **Step 4: Run manager tests and commit**

Run `MotivationActivityTests` and the existing `MotivationTests`; expected:
all PASS.

```bash
git add Haiity/Services/MotivationActivityManager.swift \
  Haiity/Intents/MotivationActivityIntents.swift \
  HaiityTests/MotivationActivityTests.swift
git commit -m "Add motivation Live Activity reconciliation"
```

### Task 3: Widget Rendering And Target Wiring

**Files:**
- Create: `HaiityWidget/MotivationActivity.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `project.yml`
- Modify: `HaiityTests/MotivationActivityTests.swift`

**Interfaces:**
- Consumes `MotivationActivityAttributes` and
  `DismissMotivationActivityIntent` from Tasks 1-2.
- Produces one `MotivationLiveActivity` in the existing
  `HaiityWidgetBundle`.

- [ ] **Step 1: Write failing extension and bundle contracts**

Add source contracts that assert:

```swift
let widget = try source("HaiityWidget/MotivationActivity.swift")
let bundle = try source("HaiityWidget/HaiityWidget.swift")
let yml = try source("project.yml")
XCTAssertTrue(widget.contains("ActivityConfiguration(for: MotivationActivityAttributes.self)"))
XCTAssertTrue(widget.contains("DismissMotivationActivityIntent"))
XCTAssertTrue(bundle.contains("MotivationLiveActivity()"))
XCTAssertTrue(yml.contains("Haiity/Models/MotivationActivity.swift"))
XCTAssertTrue(yml.contains("Haiity/Intents/MotivationActivityIntents.swift"))
XCTAssertTrue(yml.contains("NSSupportsLiveActivities: true"))
```

Run the focused test; expected: FAIL because the extension view and target
source entries do not exist.

- [ ] **Step 2: Implement Lock Screen and Dynamic Island surfaces**

Create `MotivationLiveActivity` with these surfaces:

- Lock Screen: compact quote-bubble symbol, captured title, body, and one
  `Button(intent: DismissMotivationActivityIntent())` labeled `Ausblenden`.
- Dynamic Island compact leading: quote-bubble symbol; compact trailing:
  `Text(context.attributes.title).lineLimit(1)`.
- Dynamic Island minimal: quote-bubble symbol.
- Dynamic Island expanded: title/body in the bottom region and the same
  dismissal button.

Do not add a timer, progress bar, habit completion button, or network read to
the extension. Use the captured attributes only; all message text is already
localized by `Motivation.message` in the app process.

- [ ] **Step 3: Wire shared sources into the extension**

Add the model and intent paths to the `HaiityWidget` target in `project.yml`
beside the existing habit-session model/intent paths. Keep
`NSSupportsLiveActivities: true` in both generated Info.plists. Add
`MotivationLiveActivity()` immediately after `HabitSessionLiveActivity()` in
the widget bundle.

- [ ] **Step 4: Run contracts and commit**

Run `MotivationActivityTests` and `MotivationTests`; expected: PASS. Regenerate
the Xcode project after changing `project.yml`.

```bash
xcodegen generate
git add HaiityWidget/MotivationActivity.swift HaiityWidget/HaiityWidget.swift \
  project.yml HaiityTests/MotivationActivityTests.swift
git commit -m "Render motivation Live Activity surfaces"
```

### Task 4: GitHub Tile Startup Splash

**Files:**
- Create: `Haiity/Views/StartupSplashView.swift`
- Create: `HaiityTests/StartupSplashTests.swift`
- Modify: `Haiity/HaiityApp.swift`

**Interfaces:**
- Produces `StartupSplashPhase`, `StartupSplashTimeline`, and
  `StartupSplashView` for the app root.
- Uses only local SwiftUI state and the existing `Theme.level`,
  `PaletteStyle.default`, `GridCell`, and GitHub tile conventions. It does not
  read `GitHubContributionStore`.

- [ ] **Step 1: Write failing timeline and determinism tests**

Use this stable phase API:

```swift
enum StartupSplashPhase: Equatable {
    case cluster
    case spread
    case zoom
    case reveal
}

enum StartupSplashTimeline {
    static let clusterDuration: TimeInterval = 0.30
    static let spreadDuration: TimeInterval = 0.78
    static let zoomDuration: TimeInterval = 0.72
    static let totalDuration: TimeInterval = 1.80

    static func phase(at elapsed: TimeInterval) -> StartupSplashPhase
    static func placeholderLevels(columns: Int, rows: Int) -> [Int]
}
```

Assert that negative/zero elapsed time is `.cluster`, the three boundaries
produce the expected phases, elapsed time at/after `totalDuration` is
`.reveal`, and `placeholderLevels(columns: 13, rows: 7)` is stable, has 91
values, and contains only levels `0...4`. Add a source contract that the app
root contains `StartupSplashView`, hides `ContentView` before completion, and
does not replace the static `UILaunchScreen` configuration with a fake launch
asset.

Run the focused tests; expected: FAIL because the timeline and root overlay do
not exist.

- [ ] **Step 2: Implement the deterministic tile field and animation**

Create `StartupSplashView` with:

```swift
struct StartupSplashView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: StartupSplashPhase = .cluster
    private let levels = StartupSplashTimeline.placeholderLevels(columns: 13, rows: 7)

    var body: some View {
        ZStack {
            ForEach(Array(levels.enumerated()), id: \.offset) { item in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.level(item.element,
                                      dark: colorScheme == .dark,
                                      palette: PaletteStyle.default))
                    .frame(width: 14, height: 14)
                    .offset(tileOffset(for: item.offset))
                    .scaleEffect(tileScale)
                    .opacity(tileOpacity)
            }
        }
        .task { await play() }
    }
}
```

Render a centered 13-by-7 field with fixed levels from
`placeholderLevels`; implement `tileOffset(for:)`, `tileScale`, and
`tileOpacity` from the current phase and tile index. In `.cluster`, translate
all tiles toward the center and scale the field down. In `.spread`, animate
each tile from its center origin to its grid coordinate with a deterministic
per-index delay. In `.zoom`, scale the grid field past the viewport while the
tile positions continue outward. At `.reveal`, call `onFinished` without an
animation transaction so the app page appears atomically. Use the existing
GitHub green ramp for all levels and the current system background for the
splash surface.

On `onAppear`, schedule the three phase changes with the constants above and
call `onFinished` after the full 1.80-second sequence. Under Reduce Motion,
keep the same phase timing and final handoff but use opacity/scale changes
without per-tile translation.

- [ ] **Step 3: Place the splash above the app root**

Change `HaiityApp.body` to keep `ContentView` mounted for its existing boot
task while hiding it until the splash completes:

```swift
@State private var startupFinished = false

ZStack {
    ContentView()
        .opacity(startupFinished ? 1 : 0)
        .allowsHitTesting(startupFinished)
        .accessibilityHidden(!startupFinished)
    if !startupFinished {
        StartupSplashView {
            withTransaction(Transaction(animation: nil)) {
                startupFinished = true
            }
        }
        .zIndex(1)
    }
}
```

Keep the existing notification delegate, session recovery, debug launch
arguments, and scene-phase behavior unchanged. The splash must not use a
network-backed GitHub snapshot or delay `ContentView`'s local boot.

- [ ] **Step 4: Run tests and commit the splash**

Run `StartupSplashTests`, build the app target, and commit only the splash
files:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:HaiityTests/StartupSplashTests
git add Haiity/Views/StartupSplashView.swift Haiity/HaiityApp.swift \
  HaiityTests/StartupSplashTests.swift
git commit -m "Add GitHub tile startup splash"
```

### Task 5: Integrate Motivation Reconciliation And Localization

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/MotivationTests.swift`
- Modify: `HaiityTests/MotivationActivityTests.swift`

**Interfaces:**
- Consumes `MotivationActivityManager.shared.reconcile(...)` from Task 2.
- Produces one app lifecycle path for starting/stopping motivation activities.

- [ ] **Step 1: Write failing lifecycle contracts**

Extend source tests to require all three triggers in `ContentView.swift`:

```swift
XCTAssertTrue(content.contains("MotivationActivityManager.shared.reconcile"))
XCTAssertTrue(content.contains("await boot()"))
XCTAssertTrue(content.contains("phase == .active"))
XCTAssertTrue(content.contains("store.onChange"))
```

Add a test that the existing `Reminders.reschedule` call remains present and
that no second motivation notification planner or remote push token is
introduced.

Run the focused tests; expected: FAIL because ContentView has no activity
reconciliation calls and the new localization keys are absent.

- [ ] **Step 2: Add one ContentView helper and wire the existing hooks**

Add a private helper that passes the current local setting and effective name:

```swift
private func reconcileMotivationActivity() {
    Task {
        await MotivationActivityManager.shared.reconcile(
            motivationMinutes: store.motivationMinutes,
            name: PersonalName.effective)
    }
}
```

Call it after local boot has loaded and synchronized the store, from the
existing active-scene branch after `store.reloadFromDisk()`, and from the
existing `store.onChange` closure after reminder rescheduling is queued. Do
not add a new setting or change the existing `MoreView` motivation controls.
The manager actor handles duplicate calls from a setting change and a scene
activation arriving together.

- [ ] **Step 3: Add compact activity strings to every localization**

Add these source keys to `Haiity/Localizable.xcstrings` with German source
values and translations for every existing locale:

| Key | German source |
| --- | --- |
| `Ausblenden` | `Ausblenden` |
| `Motivation` | `Motivation` |

Use `Ausblenden` for the Live Activity intent and accessibility label. Do not
add explanatory paragraphs to the activity; the captured motivation title and
body already carry the message.

- [ ] **Step 4: Run integration tests and commit**

Run `MotivationTests`, `MotivationActivityTests`, and the existing reminder
tests. Expected: all PASS, with local notification planning unchanged.

```bash
git add Haiity/Views/ContentView.swift Haiity/Localizable.xcstrings \
  HaiityTests/MotivationTests.swift HaiityTests/MotivationActivityTests.swift
git commit -m "Start motivation activity from app lifecycle"
```

### Task 6: Full Verification And Release-Gate Update

**Files:**
- Modify: `tools/release.sh`
- Modify: only files implicated by observed build or runtime defects.

**Interfaces:**
- Consumes the complete splash and motivation activity implementation.
- Produces a passing test floor, screenshot-verified startup behavior, and an
  honest runtime report. It does not upload to TestFlight.

- [ ] **Step 1: Regenerate and run the complete suite**

Re-read all modified files, confirm the unrelated GitHub edits are still
present, then generate and test:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: every test passes. Capture the exact executed count and update
`MIN_TESTS` in `tools/release.sh` to that count, preserving the existing
historical comment style and never lowering the floor.

- [ ] **Step 2: Inspect the startup animation on the simulator**

Build/install the current app on an available iOS 27 simulator, launch it from
a terminated state, and record the startup sequence. Capture frames showing:

- centered compact tile cluster;
- spread contribution-grid geometry;
- center zoom with tiles beyond the viewport;
- atomic reveal of the real habit page.

Inspect the frames in light and dark appearance. Repeat with Reduce Motion
enabled and confirm the handoff remains visible, the underlying page is not
interactive during the splash, and no graph/network loading state is used.

- [ ] **Step 3: Exercise the motivation activity with a debug fixture**

Add and use a DEBUG-only launch argument `-demo-motivation-activity` that calls
the manager with a deterministic enabled time of `00:00` and the current day,
without changing release behavior or persisted user settings. Launch the app
with the argument after installing a fresh build, then inspect the Lock Screen
and Dynamic Island surfaces. Verify the captured title/body, compact/minimal
surfaces, expanded dismissal action, no duplicate after relaunch, and no
recreation after dismissing it. Remove or keep only this DEBUG fixture in the
same form as the existing test launch arguments; it must not affect release
configuration.

- [ ] **Step 4: Run the release verification script without upload**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./tools/release.sh
```

Expected: project generation, test floor, archive validation, bundle
manifest checks, and secret scanning pass. Do not use `--upload` in this
task.

- [ ] **Step 5: Commit verification-only changes**

Review `git diff` and `git status` to ensure no visual-companion artifacts or
unrelated GitHub edits are staged. Commit only the release-floor or runtime
fixes made for this feature:

```bash
git add tools/release.sh
git commit -m "Verify startup splash and motivation activity release"
```

Run the final commit command only when `tools/release.sh` has a
verification change. If the release gate requires no source adjustment,
leave it unchanged and report that no verification-only commit was necessary.
