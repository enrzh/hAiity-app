# Motivation Feed And Notification Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in cached open-source motivation feed and replace each habit/reminder notification toggle with `Aus`, `Standard`, or `Zeitkritisch`, while preserving offline behavior, timer sessions, iCloud compatibility, and older JSON files.

**Architecture:** Keep the existing bundled `Motivation` pool as the source of truth and add a small Foundation-only feed/cache value next to it. The app refreshes the cache only after opt-in; `Reminders` reads the cache synchronously during local scheduling and always falls back to bundled messages. Add an additive `HabitNotificationMode` to `Habit`, mirror the legacy boolean for old builds, and carry a `timeSensitive` flag through the existing `ReminderPlan` to the existing notification request builder.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation `URLSession`/`JSONDecoder`, UserNotifications, existing App Group storage, XCTest, XcodeGen project configuration.

## Global Constraints

- The open-source motivation setting is off by default.
- No network request is made while the open-source setting is disabled.
- No account, habit, device, or personal data is sent to the feed.
- Use HTTPS, a bounded timeout, a bounded response size, schema validation, and silent fallback.
- Keep the existing seven-day local notification scheduling budget.
- The three item modes are `Aus`, `Standard`, and `Zeitkritisch`; do not add a Critical Alerts entitlement.
- hAiity Do Not Disturb suppresses all hAiity notification scheduling, including time-sensitive items.
- Timer sessions and their existing Live Activity/end behavior remain separate from the item notification selector.
- Preserve unrelated dirty and untracked files; only add or modify files listed in each task.
- Before any task commit, inspect the listed files for pre-existing dirty hunks. If a listed file is already dirty, leave the task changes unstaged for final selective review instead of committing unrelated hunks.
- Use SimSlim-only verification; do not use DeviceHub or additional physical devices.

## File Map

- Modify `Haiity/Models/Habit.swift`: additive notification mode and legacy JSON compatibility.
- Modify `Haiity/Models/HabitStore.swift`: persisted opt-in setting, accessors, iCloud merge, and Codable compatibility.
- Create `Haiity/Models/MotivationFeed.swift`: validated feed entry, local App Group cache, and bounded refresh/clear operations.
- Modify `Haiity/Models/Motivation.swift`: additional bundled lines and deterministic selection from cached entries.
- Modify `Haiity/Services/Reminders.swift`: feed-aware motivation planning and time-sensitive notification requests.
- Modify `Haiity/Views/EditHabitSheet.swift`: replace the notification toggle with the three-state selector.
- Modify `Haiity/Views/MoreView.swift`: add the opt-in feed toggle, concise attribution, and refresh/error state.
- Modify `project.yml`: include the new shared model in the widget target because `Reminders` is compiled there and reads the shared cache.
- Modify `Haiity/Localizable.xcstrings`: add UI labels, accessibility labels, attribution, and feed states.
- Modify `HaiityTests/MotivationTests.swift`: content pool, feed, and setting contracts.
- Modify `HaiityTests/HabitTimeTests.swift`: item editor and notification-mode contracts.
- Modify `HaiityTests/ReminderUpcomingTests.swift`: scheduling and interruption-level coverage.
- Create `HaiityTests/MotivationFeedTests.swift`: isolated feed decoder, cache, and refresh tests.

### Task 1: Add the notification-mode model with migration tests

**Files:**
- Modify: `Haiity/Models/Habit.swift`
- Modify: `HaiityTests/HabitTimeTests.swift`

**Interfaces:**
- Produce `HabitNotificationMode: String, Codable, CaseIterable, Sendable` with `.off`, `.standard`, and `.timeSensitive`.
- Produce `Habit.notificationMode` as the stored source of truth.
- Preserve `Habit.notificationsEnabled` as a computed compatibility property.

- [ ] **Step 1: Write failing migration and round-trip tests**

Add tests beside the existing `notificationsEnabled` tests:

```swift
func testLegacyNotificationBooleanMigratesToStandardOrOff() throws {
    let id = UUID().uuidString
    let enabled = "{\"id\":\"\(id)\",\"name\":\"Lesen\",\"createdAt\":\"2026-01-01\",\"log\":{}}"
    let disabled = "{\"id\":\"\(id)\",\"name\":\"Lesen\",\"createdAt\":\"2026-01-01\",\"notificationsEnabled\":false,\"log\":{}}"

    XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: Data(enabled.utf8)).notificationMode, .standard)
    XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: Data(disabled.utf8)).notificationMode, .off)
}

func testTimeSensitiveModePreservesLegacyEnabledMirror() throws {
    var habit = Habit(name: "Lesen", notificationMode: .timeSensitive)
    XCTAssertTrue(habit.notificationsEnabled)
    habit.notificationsEnabled = false
    XCTAssertEqual(habit.notificationMode, .off)

    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(habit)) as? [String: Any]
    XCTAssertEqual(json?["notificationMode"] as? String, "off")
    XCTAssertEqual(json?["notificationsEnabled"] as? Bool, false)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/HabitTimeTests
```

Expected: compile failure because `HabitNotificationMode` and the new initializer do not exist.

- [ ] **Step 3: Implement the minimal additive model**

Add the enum and change `Habit` as follows:

```swift
enum HabitNotificationMode: String, Codable, CaseIterable, Sendable {
    case off
    case standard
    case timeSensitive

    var isEnabled: Bool { self != .off }
}
```

Store `notificationMode`, keep the initializer argument
`notificationsEnabled: Bool = true`, and add an optional
`notificationMode: HabitNotificationMode? = nil` argument that wins when supplied.
Decode `notificationMode` first and otherwise map the legacy boolean (defaulting to
`true`). Encode the new value when it is not `.standard`, and always encode the
legacy boolean when needed so old builds see `.standard` and `.timeSensitive` as enabled.
Make `notificationsEnabled` computed so existing callers continue to compile.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run the same command from Step 2. Expected: PASS, including all existing habit-time tests.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/Habit.swift HaiityTests/HabitTimeTests.swift
git commit -m "Add per-item notification modes"
```

### Task 2: Persist the optional motivation-feed setting

**Files:**
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `HaiityTests/MotivationTests.swift`

**Interfaces:**
- Add `HabitData.openSourceMotivationEnabled: Bool` with default `false`.
- Add `HabitStore.openSourceMotivationEnabled` getter/setter using the existing `persist()` path.

- [ ] **Step 1: Write failing Codable and iCloud-merge tests**

```swift
func testOpenSourceMotivationDefaultsOffAndRoundTrips() throws {
    XCTAssertFalse(HabitData.empty.openSourceMotivationEnabled)
    var data = HabitData.empty
    data.openSourceMotivationEnabled = true
    let decoded = try JSONDecoder().decode(HabitData.self,
        from: JSONEncoder().encode(data))
    XCTAssertTrue(decoded.openSourceMotivationEnabled)
}

func testOlderHabitDataWithoutFeedSettingRemainsOff() throws {
    let decoded = try JSONDecoder().decode(HabitData.self,
        from: Data("{\"version\":2,\"updatedAt\":0,\"habits\":[]}".utf8))
    XCTAssertFalse(decoded.openSourceMotivationEnabled)
}
```

- [ ] **Step 2: Run `MotivationTests` and verify the new tests fail**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/MotivationTests
```

Expected: compile failure for the missing property.

- [ ] **Step 3: Add the additive field and existing-store accessors**

Add the field to `HabitData`, initialize it to `false`, decode with
`decodeIfPresent(... ) ?? false`, and encode only when `true` to preserve compact
legacy payloads. Add the `HabitStore` computed property beside the existing motivation
properties. Include the field in the existing newer-payload merge branch so the opt-in
choice follows the same iCloud preference freshness rules as motivation delivery.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/HabitStore.swift HaiityTests/MotivationTests.swift
git commit -m "Persist optional open-source motivation setting"
```

### Task 3: Add the validated local cache and bounded feed refresh

**Files:**
- Create: `Haiity/Models/MotivationFeed.swift`
- Modify: `project.yml`
- Create or modify: `HaiityTests/MotivationFeedTests.swift`

**Interfaces:**
- Produce `MotivationFeedEntry: Codable, Equatable, Sendable` with `text`, `language`, and optional `author`.
- Produce `MotivationFeedCache.load(in:)`, `save(_:receivedAt:in:)`, and `clear(in:)`.
- Produce `MotivationFeed.refreshIfNeeded(enabled:now:defaults:transport:) async`.
- Keep the transport injectable as a closure, not a new protocol or service layer:
  `(URLRequest) async throws -> (Data, HTTPURLResponse)`.

- [ ] **Step 1: Write failing feed-validation and cache tests**

Cover a valid entry, invalid JSON, empty/overlong text, unsupported language,
stale-cache refresh, fresh-cache no-op, disabled no-op, and clear-on-disable.
Use an in-memory `UserDefaults(suiteName: UUID().uuidString)` and a closure transport.

```swift
func testValidFeedIsFilteredAndCached() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let response = HTTPURLResponse(url: URL(string: "https://example.com/feed.json")!,
                                   statusCode: 200, httpVersion: nil, headerFields: nil)!
    let payload = Data("{\"version\":1,\"entries\":[{\"text\":\"Keep going.\",\"language\":\"en\"},{\"text\":\"\",\"language\":\"en\"}]}".utf8)

    let result = try await MotivationFeed.refreshIfNeeded(
        enabled: true, now: Date(timeIntervalSince1970: 100_000), defaults: defaults) { _ in
            (payload, response)
        }

    XCTAssertEqual(result.map(\.text), ["Keep going."])
    XCTAssertEqual(MotivationFeedCache.load(in: defaults).map(\.text), ["Keep going."])
}

func testDisabledFeedNeverCallsTransportAndClearsCache() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    MotivationFeedCache.save([MotivationFeedEntry(text: "Old", language: "en")],
                             receivedAt: .now, in: defaults)
    var calls = 0
    let result = try await MotivationFeed.refreshIfNeeded(
        enabled: false, now: .now, defaults: defaults) { _ in
            calls += 1
            throw URLError(.badServerResponse)
        }

    XCTAssertTrue(result.isEmpty)
    XCTAssertEqual(calls, 0)
    XCTAssertTrue(MotivationFeedCache.load(in: defaults).isEmpty)
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/MotivationFeedTests
```

Expected: compile failure because the feed/cache types do not exist.

- [ ] **Step 3: Implement the feed with a pinned source and safe cache**

Use a fixed HTTPS raw URL pinned to the audited commit
`https://raw.githubusercontent.com/mubaris/motivate/ff66d015fe9f6017444ea709f8e3217a0537c4cd/200.json`
only after retaining the repository attribution and confirming the data file's rights
are sufficient for redistribution. If that content audit fails, do not ship the URL;
use a repository-owned feed containing only verified public-domain/CC0 entries instead.

Normalize the source's `quote`/`author` shape into the app's `text`/`author` shape.
Reject non-2xx responses, payloads over 128 KiB, empty text, entries over 140 Unicode
scalars, entries without a supported language, and more than 200 entries. Use a seven-day
cache age, a 10-second request timeout, and `URLSession.shared.data(for:)`. Store only
validated JSON and the receive date in the App Group defaults; never store it in iCloud.

- [ ] **Step 4: Add target membership and run feed tests**

Add `Haiity/Models/MotivationFeed.swift` to the widget target because `Reminders` in that
target must read the same cached entries after a widget check-in. The extension never
calls the network refresh method. Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/MotivationFeed.swift HaiityTests/MotivationFeedTests.swift project.yml
git commit -m "Add opt-in motivation feed cache"
```

### Task 4: Expand motivation selection and local notification scheduling

**Files:**
- Modify: `Haiity/Models/Motivation.swift`
- Modify: `Haiity/Services/Reminders.swift`
- Modify: `HaiityTests/MotivationTests.swift`
- Modify: `HaiityTests/ReminderUpcomingTests.swift`

**Interfaces:**
- Add `Motivation.message(name:today:additionalEntries:)` while preserving the existing overload.
- Add `ReminderPlan.timeSensitive: Bool = false`.
- Map `HabitNotificationMode.timeSensitive` to that plan field.

- [ ] **Step 1: Write failing selection and interruption-level tests**

Assert that an additional valid entry can be selected deterministically, bundled text
still works when the additional pool is empty, `.off` creates no habit plan, and a
time-sensitive plan produces `.timeSensitive` on the final notification content.

```swift
func testAdditionalMotivationEntryIsStableForTheDay() {
    let entry = MotivationFeedEntry(text: "A cached line", language: "en")
    let first = Motivation.message(name: nil, today: "2026-09-01", additionalEntries: [entry])
    let second = Motivation.message(name: nil, today: "2026-09-01", additionalEntries: [entry])
    XCTAssertEqual(first.title, second.title)
    XCTAssertEqual(first.body, second.body)
}

func testNotificationRequestUsesTimeSensitiveInterruptionLevel() {
    let plan = ReminderPlan(identifier: "test", title: "Test", body: "Body",
                            dateMatching: DateComponents(year: 2026, month: 9, day: 1),
                            repeats: false, timeSensitive: true)
    XCTAssertEqual(Reminders.request(plan).content.interruptionLevel, .timeSensitive)
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/MotivationTests \
  -only-testing:HaiityTests/ReminderUpcomingTests
```

Expected: compile failure for the new overload/plan field, or assertion failure before implementation.

- [ ] **Step 3: Implement feed-aware selection and scheduling**

Keep openers local and use cached feed entries only for the body pool when the current
language matches. Seed the existing stable index with the day key and a feed-version/cache
marker so a given cache snapshot remains deterministic. In `Reminders.reschedule`, load
the validated cache, pass it to `motivationPlans`, and keep the existing seven-day budget.

Add `timeSensitive` to `ReminderPlan`, set it from `habit.notificationMode`, and filter
`.off` items before creating plans. In `Reminders.request(_:)`, set
`content.interruptionLevel = .timeSensitive` only when the flag is true; leave all other
notifications at the system default.

- [ ] **Step 4: Run focused tests and verify they pass**

Run the command from Step 2. Expected: PASS, including existing budget and reminder tests.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Models/Motivation.swift Haiity/Services/Reminders.swift \
  HaiityTests/MotivationTests.swift HaiityTests/ReminderUpcomingTests.swift
git commit -m "Use cached motivation content and notification modes"
```

### Task 5: Replace the editor toggle with the three-state control

**Files:**
- Modify: `Haiity/Views/EditHabitSheet.swift`
- Modify: `HaiityTests/HabitTimeTests.swift`

**Interfaces:**
- Replace editor state `notificationsEnabled` with `notificationMode`.
- Persist `habit.notificationMode` during save and load.
- Keep permission prompting only when selecting `.standard` or `.timeSensitive` for a timed item.

- [ ] **Step 1: Write failing source-contract tests**

Assert the editor contains a one-of-three selector and no standalone notification toggle:

```swift
func testEditorUsesThreeStateNotificationMode() throws {
    let source = try source("Haiity/Views/EditHabitSheet.swift")
    XCTAssertTrue(source.contains("notificationMode"))
    XCTAssertTrue(source.contains(".timeSensitive"))
    XCTAssertTrue(source.contains("habit-notification-mode"))
    XCTAssertFalse(source.contains("habit-notification-toggle"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/HabitTimeTests/testEditorUsesThreeStateNotificationMode
```

Expected: assertion failure because the old toggle remains.

- [ ] **Step 3: Implement the native selector and migration-aware save path**

Use a localized `Picker` with `.pickerStyle(.segmented)` and the short labels
`Aus`, `Standard`, and `Zeitkritisch`. Hide it when `draft.hasTime` is false. Load
`existing.notificationMode`, save `habit.notificationMode`, and keep the time-change
permission gate conditional on `notificationMode.isEnabled`. If the user switches a
timed item to `.off`, do not request permission; if they select either enabled mode,
use the existing `requestNotificationPermissionIfNeeded()` flow.

- [ ] **Step 4: Run editor and model tests**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/HabitTimeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Views/EditHabitSheet.swift HaiityTests/HabitTimeTests.swift
git commit -m "Expose three notification modes in item editor"
```

### Task 6: Add the opt-in feed UI and attribution

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/MotivationTests.swift`

**Interfaces:**
- Add a toggle with accessibility identifier `motivation-open-source-toggle`.
- Add a concise source attribution row and a refresh result state.
- Enabling fetches asynchronously, keeps built-in messages active immediately, then calls the existing reschedule path when cache refresh completes.

- [ ] **Step 1: Write failing UI contract tests**

```swift
func testMoreCarriesOptInOpenSourceMotivationSetting() throws {
    let source = try source("Haiity/Views/MoreView.swift")
    XCTAssertTrue(source.contains("motivation-open-source-toggle"))
    XCTAssertTrue(source.contains("openSourceMotivationEnabled"))
    XCTAssertTrue(source.contains("Quelle"))
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/MotivationTests/testMoreCarriesOptInOpenSourceMotivationSetting
```

Expected: assertion failure because the feed setting is absent.

- [ ] **Step 3: Implement the concise optional setting**

Place it next to the existing daily motivation controls. Keep the copy short:
`Zusätzliche offene Nachrichten` / `Optional aus einer offenen Quelle`. On enable,
set the persisted preference first, launch the bounded refresh, and leave built-in
messages available while loading. On disable, clear the cache and call the existing
reschedule path. Show attribution only when the feature is enabled, with a link to
the source repository and its license. Show a non-blocking retry hint after a failed
refresh without exposing raw errors or URLs in a notification.

- [ ] **Step 4: Add localization entries and run focused tests**

Add German source strings plus English values for the toggle, description, source,
license, loading, and unavailable states. Let the existing localization extraction
continue generating other translations. Run `MotivationTests`; expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Haiity/Views/MoreView.swift Haiity/Localizable.xcstrings HaiityTests/MotivationTests.swift
git commit -m "Add opt-in open-source motivation setting"
```

### Task 7: Verify iCloud, DND, timer separation, and release behavior

**Files:**
- Modify: `HaiityTests/MotivationTests.swift`
- Modify: `HaiityTests/ReminderUpcomingTests.swift`
- Modify: `HaiityTests/HabitTimeTests.swift`

- [ ] **Step 1: Run all focused regression tests**

```bash
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  -only-testing:HaiityTests/MotivationTests \
  -only-testing:HaiityTests/MotivationFeedTests \
  -only-testing:HaiityTests/HabitTimeTests \
  -only-testing:HaiityTests/ReminderUpcomingTests \
  -only-testing:HaiityTests/ProGateTests
```

Expected: all focused tests pass. Existing unrelated full-suite failures remain separately reported rather than hidden.

- [ ] **Step 2: Run source and project checks**

```bash
git diff --check
xcodegen generate
xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'
```

Expected: no whitespace errors, project generation succeeds, and the app plus widget test bundle builds.

- [ ] **Step 3: SimSlim verification**

Install the test build through SimSlim and verify only these flows: enable/disable the
open-source setting, offline fallback, a standard item notification, a time-sensitive
item notification, an off item with no request, DND suppression, and a timer session
start/finish. Confirm the old existing habit JSON still loads and the editor preserves
the selected mode after relaunch.

- [ ] **Step 4: Review the final diff and commit integration**

```bash
git status --short
git diff --stat
git diff --check
```

Review the final diff and stage only the exact files changed by this plan. Do not use
`git add Haiity` or `git add HaiityTests` because the current worktree already contains
unrelated modifications in those directories. Commit only after confirming the staged
diff contains no unrelated hunks:

```bash
git add Haiity/Models/Habit.swift Haiity/Models/HabitStore.swift \
  Haiity/Models/Motivation.swift Haiity/Models/MotivationFeed.swift \
  Haiity/Services/Reminders.swift Haiity/Views/EditHabitSheet.swift \
  Haiity/Views/MoreView.swift Haiity/Localizable.xcstrings \
  HaiityTests/HabitTimeTests.swift HaiityTests/MotivationTests.swift \
  HaiityTests/MotivationFeedTests.swift HaiityTests/ReminderUpcomingTests.swift \
  project.yml
git diff --cached --check
git commit -m "Integrate motivation and notification mode updates"
```

Do not stage unrelated `.superpowers`, fixture, or user-modified files.
