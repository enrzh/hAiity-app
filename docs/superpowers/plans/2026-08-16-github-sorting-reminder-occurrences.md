# GitHub, Sorting, and Reminder Occurrences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put GitHub account controls on More, show a Done toolbar action during sorting, and make reminder rows and completion operate on scheduled occurrences.

**Architecture:** Add one pure `ReminderOccurrenceEngine` that derives actionable occurrences from `Habit.recurrence`, `Habit.log`, and an injected clock/calendar. Persist one additive policy flag and, for non-continuing reminders, one schedule cursor on `Habit`; the row, completion actions, editor, and notification planner consume the same engine. Keep GitHub lifecycle in `GitHubContributionStore` and edit mode in `ContentView`.

**Tech Stack:** Swift 6, SwiftUI, Observation, Foundation `Calendar`, UserNotifications, XCTest, XcodeGen.

## Global Constraints

- German interface copy remains compact.
- Existing reminder history and GitHub credentials must migrate without destructive writes.
- Existing reminders decode with `repeatsWhileIncomplete == true`.
- Calendar and timezone calculations must accept an injected `Calendar` and `Date`.
- No second GitHub account state, reminder database, or top-level page.
- UI claims require simulator screenshots.

---

### Task 1: Reminder Occurrence Engine And Persistence

**Files:**
- Create: `Haiity/Models/ReminderOccurrence.swift`
- Create: `HaiityTests/ReminderOccurrenceTests.swift`
- Modify: `Haiity/Models/Habit.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `Habit.recurrence`, `Habit.createdAt`, `Habit.timeMinutes`, `Habit.reminderMinutes`, `Habit.log`, `DayKey`.
- Produces: `Habit.repeatsWhileIncomplete: Bool`, `ReminderOccurrence`, `ReminderOccurrenceState`, and `ReminderOccurrenceEngine.state(for:now:calendar:)`.

- [ ] **Step 1: Write failing persistence and occurrence tests**

Create `ReminderOccurrenceTests` with a fixed Berlin calendar and tests that assert:

```swift
func testExistingReminderDefaultsToContinuingWhileIncomplete() throws {
    let original = Habit(name: "Tabletten", itemType: .reminder)
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
    var legacy = object
    legacy.removeValue(forKey: "repeatsWhileIncomplete")
    let data = try JSONSerialization.data(withJSONObject: legacy)
    XCTAssertTrue(try JSONDecoder().decode(Habit.self, from: data).repeatsWhileIncomplete)
}

func testDisabledContinuationRoundTrips() throws {
    var reminder = Habit(name: "Tabletten", itemType: .reminder)
    reminder.repeatsWhileIncomplete = false
    XCTAssertFalse(try JSONDecoder().decode(Habit.self,
        from: JSONEncoder().encode(reminder)).repeatsWhileIncomplete)
}

func testFutureOccurrenceUsesScheduledDayAndTime() {
    var reminder = fixture(createdAt: "2026-08-16", timeMinutes: 18 * 60)
    reminder.recurrence = .weekdays([2], start: "2026-08-16")
    let state = ReminderOccurrenceEngine.state(for: reminder,
        now: date("2026-08-16", 12 * 60), calendar: calendar)
    XCTAssertEqual(state.actionable?.day, "2026-08-17")
    XCTAssertEqual(state.actionable?.dueDate, date("2026-08-17", 18 * 60))
    XCTAssertEqual(state.overdueCount, 0)
}

func testContinuationKeepsOldestOverdueAndCountsBacklog() {
    let reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
    let state = ReminderOccurrenceEngine.state(for: reminder,
        now: date("2026-08-16", 12 * 60), calendar: calendar)
    XCTAssertEqual(state.actionable?.day, "2026-08-14")
    XCTAssertEqual(state.overdueCount, 3)
}

func testDisabledContinuationKeepsOneOverdueOccurrence() {
    var reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
    reminder.repeatsWhileIncomplete = false
    let state = ReminderOccurrenceEngine.state(for: reminder,
        now: date("2026-08-16", 12 * 60), calendar: calendar)
    XCTAssertEqual(state.actionable?.day, "2026-08-14")
    XCTAssertEqual(state.overdueCount, 1)
}

func testCompletionAdvancesToFirstFutureOccurrenceWhenContinuationIsDisabled() {
    var reminder = fixture(createdAt: "2026-08-14", timeMinutes: 9 * 60)
    reminder.repeatsWhileIncomplete = false
    reminder.log["2026-08-14"] = 1
    let state = ReminderOccurrenceEngine.state(for: reminder,
        now: date("2026-08-16", 12 * 60), calendar: calendar)
    XCTAssertEqual(state.actionable?.day, "2026-08-17")
}
```

The fixture sets `.daily` recurrence unless a test overrides it. The date helper creates a local date from a day key plus minutes.

- [ ] **Step 2: Regenerate the Xcode project and run the focused tests to verify failure**

Run:

```bash
xcodegen generate
xcodebuild test -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:HaiityTests/ReminderOccurrenceTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `repeatsWhileIncomplete` and `ReminderOccurrenceEngine` do not exist.

- [ ] **Step 3: Add the additive Habit field and merge behavior**

Add:

```swift
var repeatsWhileIncomplete: Bool
```

Initialize it to `true`, decode a missing key as `true`, and encode only `false` to preserve compact backward-compatible JSON. Add the coding key. In `HabitStore.merge`, copy the remote value in the same newer-record branch that copies `itemType`, recurrence, time, and calendar participation.

- [ ] **Step 4: Implement the pure occurrence engine**

Create these exact public-to-module types:

```swift
struct ReminderOccurrence: Equatable, Sendable {
    let day: String
    let dueDate: Date
}

struct ReminderOccurrenceState: Equatable, Sendable {
    let actionable: ReminderOccurrence?
    let overdueCount: Int
    let mostRecentCompleted: ReminderOccurrence?
}

enum ReminderOccurrenceEngine {
    static func state(for reminder: Habit, now: Date = .now,
                      calendar: Calendar = .current) -> ReminderOccurrenceState
}
```

Use `max(reminder.createdAt, reminder.recurrence.start ?? reminder.createdAt)` as the history floor. Scheduled dates come from `recurrence.schedule(calendar:)`; completion is `log[day] != nil`. Build `dueDate` from the local day plus sanitized reminder time, using start-of-day when no time exists. With continuation enabled, choose the oldest unfinished scheduled day through today, otherwise the next future scheduled day. With continuation disabled, retain only the first unfinished historical occurrence; once it is completed, skip missed dates and choose the first schedule after `now`. Bound scans to valid start/end ranges and use `Recurrence.Schedule.next(after:)` instead of unbounded day loops.

- [ ] **Step 5: Run focused tests and commit**

Run the focused command from Step 2. Expected: 6 tests pass.

```bash
git add Haiity/Models/Habit.swift Haiity/Models/HabitStore.swift \
  Haiity/Models/ReminderOccurrence.swift HaiityTests/ReminderOccurrenceTests.swift \
  Haiity.xcodeproj project.yml
git commit -m "Model dated reminder occurrences"
```

---

### Task 2: Reminder Editor, Row Text, And Completion Confirmation

**Files:**
- Modify: `Haiity/Views/EditHabitSheet.swift`
- Modify: `Haiity/Views/ReminderRow.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityTests/ReminderOccurrenceTests.swift`
- Modify: `HaiityTests/ReminderItemTests.swift`

**Interfaces:**
- Consumes: `ReminderOccurrenceEngine.state(for:now:calendar:)`, `HabitStore.setValue`, `HabitStore.clear`.
- Produces: `ReminderOccurrenceText.label(for:now:calendar:locale:)` and occurrence-aware Done/revert handlers.

- [ ] **Step 1: Write failing formatter and source-contract tests**

Add four assertions covering exact German output:

```swift
XCTAssertEqual(label(due: date("2026-08-16", 18 * 60), now: date("2026-08-16", 12 * 60)),
               "Heute, 18:00")
XCTAssertEqual(label(due: date("2026-08-17", 9 * 60), now: date("2026-08-16", 12 * 60)),
               "Morgen, 09:00")
XCTAssertTrue(label(due: date("2026-08-20", 9 * 60), now: date("2026-08-16", 12 * 60))
    .contains("20.08.2026"))
XCTAssertTrue(label(due: date("2026-08-15", 9 * 60), now: date("2026-08-16", 12 * 60))
    .hasPrefix("Überfällig · "))
```

Extend `ReminderItemTests` source checks to require `repeats-while-incomplete-toggle`, `reminder-early-completion-confirm`, and to reject `RecurrenceText.summary` inside `ReminderRow`.

- [ ] **Step 2: Run focused tests to verify failure**

Run the Task 1 command with both `ReminderOccurrenceTests` and `ReminderItemTests`. Expected: formatter symbol and UI identifiers are missing.

- [ ] **Step 3: Add the reminder-only editor toggle**

Add `@State private var repeatsWhileIncomplete = true`. In the recurrence section, show this only for `.reminder`:

```swift
if itemType == .reminder {
    Toggle(String(localized: "Trotz offenem Termin wiederholen"),
           isOn: $repeatsWhileIncomplete)
        .accessibilityIdentifier("repeats-while-incomplete-toggle")
}
```

Load from and save to `habit.repeatsWhileIncomplete` alongside the other reminder fields.

- [ ] **Step 4: Render the actionable date in ReminderRow**

Give `ReminderRow` an injected `now` and `calendar` default, derive its state once, and replace recurrence summary with `ReminderOccurrenceText`. Show `Kein weiterer Termin` when no occurrence exists. Append `· +N offen` when `overdueCount > 1`. The check button reflects whether there is a recently completed occurrence only when no unfinished due occurrence is currently actionable.

- [ ] **Step 5: Route tap and swipe through one completion request**

In `ContentView`, add `@State private var earlyReminderCompletion: PendingReminderCompletion?`. Both the reminder check button and leading Done swipe call:

```swift
private func requestReminderCompletion(_ reminder: Habit) {
    let state = ReminderOccurrenceEngine.state(for: reminder)
    guard let occurrence = state.actionable else { return }
    if occurrence.dueDate > .now {
        earlyReminderCompletion = PendingReminderCompletion(habitID: reminder.id,
                                                            day: occurrence.day)
    } else {
        completeReminder(reminder, day: occurrence.day)
    }
}
```

Present a confirmation dialog titled `Vor Termin erledigen?`, with `Erledigen` carrying `reminder-early-completion-confirm` and `Abbrechen`. Confirmation writes `1` to the occurrence day through `mutate`. Revert clears `state.mostRecentCompleted?.day`. Habit-card actions continue using their current today-based methods.

- [ ] **Step 6: Run focused tests and commit**

Expected: all focused tests pass.

```bash
git add Haiity/Views/EditHabitSheet.swift Haiity/Views/ReminderRow.swift \
  Haiity/Views/ContentView.swift HaiityTests/ReminderOccurrenceTests.swift \
  HaiityTests/ReminderItemTests.swift
git commit -m "Make reminder interactions occurrence aware"
```

---

### Task 3: Notification Planning Uses The Occurrence Policy

**Files:**
- Modify: `Haiity/Services/Reminders.swift`
- Modify: `HaiityTests/ReminderUpcomingTests.swift`

**Interfaces:**
- Consumes: `ReminderOccurrenceEngine.state(for:now:calendar:)`.
- Produces: policy-aware reminder plans while leaving tracked-habit plans unchanged.

- [ ] **Step 1: Write the failing notification policy test**

```swift
func testReminderWithoutContinuationPlansOnlyItsActionableOccurrence() {
    var reminder = Habit(name: "Tabletten", itemType: .reminder,
                         timeMinutes: 18 * 60, recurrence: .daily)
    reminder.createdAt = "2026-08-09"
    reminder.repeatsWhileIncomplete = false
    let plans = Reminders.habitPlans(habits: [reminder], now: now, calendar: calendar)
    XCTAssertTrue(plans.isEmpty, "the only actionable occurrence is already overdue")

    reminder.log["2026-08-09"] = 1
    let advanced = Reminders.habitPlans(habits: [reminder], now: now, calendar: calendar)
    XCTAssertEqual(advanced.first?.identifier,
                   Reminders.habitReminderIdentifier(habitID: reminder.id,
                                                      day: "2026-08-10"))
    XCTAssertEqual(advanced.count, 1)
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run `ReminderUpcomingTests/testReminderWithoutContinuationPlansOnlyItsActionableOccurrence`. Expected: current planner emits the full future window.

- [ ] **Step 3: Apply the shared occurrence policy**

Inside `habitPlans`, keep the existing path for tracked habits and continuation-enabled reminders. For a reminder with continuation disabled, ask the occurrence engine for its actionable occurrence and emit only that day when its due date is in the future. Preserve request-budget accounting, identifiers, title, body, and one-shot triggers.

- [ ] **Step 4: Run reminder tests and commit**

Run all `ReminderUpcomingTests` and `ReminderOccurrenceTests`. Expected: pass.

```bash
git add Haiity/Services/Reminders.swift HaiityTests/ReminderUpcomingTests.swift
git commit -m "Respect unfinished reminder notification policy"
```

---

### Task 4: Direct GitHub Controls On More

**Files:**
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityTests/AppNavigationTests.swift`

**Interfaces:**
- Consumes: the existing `GitHubContributionStore.snapshot`, `.disconnect()`, and `MoreRoute.github`.
- Produces: main More row identifiers `open-github-settings` and `disconnect-github`; removes the duplicate About row.

- [ ] **Step 1: Write a failing navigation source test**

Require `MoreView` to own a `GitHubContributionStore` reference, require the main list to contain both identifiers, and assert the `AboutView` body no longer contains `NavigationLink(value: MoreRoute.github)`.

- [ ] **Step 2: Run the navigation test and verify failure**

Run only the new `AppNavigationTests` method. Expected: the main More view has no GitHub dependency or row.

- [ ] **Step 3: Pass the existing store into every MoreView**

Add `let github: GitHubContributionStore` to `MoreView`, include identity in `Equatable`, and pass the existing `ContentView.github` at all four construction sites, including appearance and habit-behavior destinations. Remove the GitHub property from `AboutView` after removing its row.

- [ ] **Step 4: Add the main More account row**

Place a GitHub section after `personalSection`. The primary borderless button opens `.github` and shows either `Verbinden` or the snapshot username. When connected, a trailing borderless destructive `Abmelden` button calls `github.disconnect()` and carries `disconnect-github`. Do not mirror phase or username into local state.

- [ ] **Step 5: Run navigation and GitHub store tests and commit**

Expected: tests pass.

```bash
git add Haiity/Views/MoreView.swift Haiity/Views/ContentView.swift \
  HaiityTests/AppNavigationTests.swift
git commit -m "Expose GitHub account controls on More"
```

---

### Task 5: Sorting Done Toolbar State

**Files:**
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityTests/AppNavigationTests.swift`

**Interfaces:**
- Consumes: `ContentView.editMode`.
- Produces: mutually exclusive `create-habit` and `finish-reordering` toolbar actions.

- [ ] **Step 1: Write the failing toolbar source test**

Assert the trailing toolbar branch contains `Image(systemName: "checkmark")`, identifier `finish-reordering`, and assigns `editMode = .inactive`; retain the existing create identifier only in the inactive branch.

- [ ] **Step 2: Run the focused test and verify failure**

Expected: no trailing checkmark branch exists.

- [ ] **Step 3: Implement the mutually exclusive toolbar item**

Replace `createToolbarItem` with a toolbar builder that renders:

```swift
if editMode == .active {
    Button {
        withAnimation { editMode = .inactive }
    } label: {
        Image(systemName: "checkmark")
    }
    .accessibilityLabel(String(localized: "Fertig"))
    .accessibilityIdentifier("finish-reordering")
} else {
    // Existing plus button, zoom source, label, and identifier unchanged.
}
```

- [ ] **Step 4: Run navigation tests and commit**

```bash
git add Haiity/Views/ContentView.swift HaiityTests/AppNavigationTests.swift
git commit -m "Show Done action while sorting habits"
```

---

### Task 6: Full Gate And Simulator Visual Verification

**Files:**
- Modify: `tools/release.sh`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified test floor and screenshots for every changed UI state.

- [ ] **Step 1: Raise the intentional unit-test floor**

Change `MIN_TESTS=1079` to `MIN_TESTS=1090`, matching the 11 new XCTest methods in this plan.

- [ ] **Step 2: Run the complete release verification without upload**

```bash
tools/release.sh
```

Expected: at least 1,090 tests, successful Release archive, export, entitlement checks, and no upload.

- [ ] **Step 3: Install and launch the Debug app in the newest iPhone simulator**

Build Debug for the simulator, install the resulting `.app`, and use `-demo-github-card` for the connected More state. Create future and overdue reminder fixtures through the real create/edit UI so the screenshots exercise shipped behavior instead of a debug-only state path.

- [ ] **Step 4: Capture and inspect screenshots**

Capture light and dark screenshots with `xcrun simctl io <UDID> screenshot <absolute-path>` for:

- More with connected GitHub username and visible `Abmelden`;
- Habits sorting with trailing checkmark and no trailing plus;
- future reminder date;
- early-completion confirmation;
- overdue reminder with backlog count.

Reject and fix clipping, duplicate toolbar controls, unreadable secondary text, or inconsistent card heights before continuing.

- [ ] **Step 5: Run `git diff --check`, inspect scope, and commit verification metadata**

```bash
git diff --check
git status --short
git add tools/release.sh
git commit -m "Verify GitHub sorting and reminder occurrence UI"
```

Do not bump the build number or upload to TestFlight unless the user asks for a release after reviewing this implementation.
