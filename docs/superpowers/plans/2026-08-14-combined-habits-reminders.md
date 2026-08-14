# Combined Habits and Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add graph-free reminder items to the combined Habits list, selected from the existing create/edit form, with shared local notifications and independently selectable Apple Calendar sync.

**Architecture:** Extend `Habit` with a backward-compatible `HabitItemType` discriminator and keep one persisted item collection. Reuse recurrence, daily logs, notification planning, archive, search, sorting, export, and iCloud merge; introduce explicit tracked-item filters at analytics boundaries and a dedicated compact reminder row at the presentation boundary. Extend the existing EventKit mirror with two device-local selection flags while keeping one permission, calendar, event map, and reconciliation engine.

**Tech Stack:** Swift 5.9, SwiftUI, EventKit, UserNotifications, WidgetKit, XCTest, XcodeGen, iOS 17 minimum with native iOS 26/27 tab APIs.

## Global Constraints

- Keep native navigation as `Statistik`, `Habits`, `Mehr`, plus the separate native Search-role button.
- Keep one create/edit form and one persisted item array; do not add a Reminder page, model store, or navigation tab.
- Existing decoded items default to `HabitItemType.habit`, including unknown malformed discriminator values.
- Reminder cards have no graph, statistics, backfill, session, Live Activity, or graph-sharing entry point.
- Reminder notification time remains the existing `Uhrzeit` value.
- Apple Calendar integration uses the existing private `hAiity` calendar, not the Apple Reminders app.
- All visible German copy must be translated for all 16 non-source locales.
- Re-read every target file immediately before editing because parallel sessions may share the repository.
- Do not claim UI correctness from source; install and inspect light/dark simulator screenshots.

---

### Task 1: Persist the Item Classification

**Files:**
- Modify: `Haiity/Models/Habit.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `HaiityTests/GoalEngineTests.swift`
- Modify: `HaiityTests/StoreAndMergeTests.swift`

**Interfaces:**
- Produces: `HabitItemType`, `Habit.itemType`, `Habit.isReminder`, `Habit.isTrackedHabit`.
- Produces: `HabitStore.activeTrackedHabits` and `HabitStore.activeReminders` while preserving `activeHabits` as the complete combined active list.
- Merge contract: newer metadata copies `itemType` with the other editable Habit fields.

- [ ] **Step 1: Write failing Codable and store-partition tests**

Add these tests to `ModelV2CodableTests` and `StoreV2Tests`:

```swift
func testMissingAndUnknownItemTypeDecodeAsHabit() throws {
    let old = Data(#"{"name":"Read","emoji":"","log":{},"createdAt":"2026-08-14"}"#.utf8)
    XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: old).itemType, .habit)

    let unknown = Data(#"{"name":"Read","emoji":"","log":{},"createdAt":"2026-08-14","itemType":"future"}"#.utf8)
    XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: unknown).itemType, .habit)
}

func testReminderRoundTripsAndPartitionsWithoutChangingOrder() throws {
    let habit = Habit(name: "Read")
    let reminder = Habit(name: "Medicine", itemType: .reminder)
    store.add(habit)
    store.add(reminder)
    XCTAssertEqual(store.activeHabits.map(\.name), ["Read", "Medicine"])
    XCTAssertEqual(store.activeTrackedHabits.map(\.name), ["Read"])
    XCTAssertEqual(store.activeReminders.map(\.name), ["Medicine"])
    XCTAssertEqual(HabitStore(url: store.url).activeReminders.first?.itemType, .reminder)
}
```

- [ ] **Step 2: Run the focused tests and verify the new symbols fail to compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests/ModelV2CodableTests \
  -only-testing:HaiityTests/StoreV2Tests CODE_SIGNING_ALLOWED=NO
```

Expected: failure because `HabitItemType`, `itemType`, and the partition properties do not exist.

- [ ] **Step 3: Implement the discriminator and tolerant decoder**

Add the model surface:

```swift
enum HabitItemType: String, Codable, CaseIterable, Sendable {
    case habit
    case reminder
}

struct Habit: Codable, Identifiable, Equatable {
    var itemType: HabitItemType

    var isReminder: Bool { itemType == .reminder }
    var isTrackedHabit: Bool { itemType == .habit }
}
```

Add `itemType` to the initializer with `.habit` default and to `CodingKeys`. Decode tolerantly so missing and unknown values cannot reject the file:

```swift
itemType = (try? c.decode(HabitItemType.self, forKey: .itemType)) ?? .habit
```

Encode only reminders to preserve compact old-compatible files:

```swift
if itemType != .habit { try c.encode(itemType, forKey: .itemType) }
```

Add store partitions:

```swift
var activeTrackedHabits: [Habit] { activeHabits.filter(\.isTrackedHabit) }
var activeReminders: [Habit] { activeHabits.filter(\.isReminder) }
```

Copy `itemType` inside the existing `remoteNewer` Habit metadata merge block.

- [ ] **Step 4: Run model, merge, and reorder suites**

Run the command from Step 2 plus `StoreAndMergeTests`, `ReorderTests`, and `CloudPayloadTests`.

Expected: all selected tests pass; mixed items keep their single-array ordering.

- [ ] **Step 5: Commit the model migration**

```bash
git add Haiity/Models/Habit.swift Haiity/Models/HabitStore.swift \
  HaiityTests/GoalEngineTests.swift HaiityTests/StoreAndMergeTests.swift
git commit -m "Add reminder item classification"
```

---

### Task 2: Establish Tracked-Habit Boundaries

**Files:**
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `Haiity/Models/StatsEngine.swift`
- Modify: `Haiity/Models/Celebration.swift`
- Modify: `Haiity/Views/StatsView.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `HaiityWidget/HaiityWidget.swift`
- Modify: `HaiityTests/StatsEngineTests.swift`
- Modify: `HaiityTests/SummaryTests.swift`
- Modify: `HaiityTests/CelebrationTests.swift`
- Modify: `HaiityTests/ProGateTests.swift`
- Modify: `HaiityTests/WidgetLogicTests.swift`

**Interfaces:**
- Consumes: `Habit.isTrackedHabit`, `HabitStore.activeTrackedHabits`.
- Produces: analytics and product limits that ignore reminders even when passed a mixed item list.
- Keeps: `HabitStore.activeHabits` for the combined list, search, sorting, archive, and reminder scheduling.

- [ ] **Step 1: Write mixed-list exclusion tests**

Cover these concrete assertions:

```swift
let tracked = Habit(name: "Read")
var reminder = Habit(name: "Medicine", itemType: .reminder)
reminder.log[today] = 1

XCTAssertEqual(StatsEngine.snapshot(habits: [tracked, reminder], today: today).todayTotal, 1)
XCTAssertFalse(store.dailyStatus(today).missing.contains("Medicine"))
XCTAssertFalse(store.weeklyStatus(today).missing.contains("Medicine"))
XCTAssertEqual(store.activeTrackedHabits.count, 1)
```

Add source/behavior tests proving widget entries and the Pro habit-count gate use `activeTrackedHabits`, while the main list still uses `activeHabits`.

- [ ] **Step 2: Run the analytics boundary suites and verify failure**

Run `StatsEngineTests`, all four Summary test classes, `CelebrationTests`, `ProGateTests`, and `WidgetLogicTests`.

Expected: reminders currently affect at least statistics, summaries, widgets, or the active-count gate.

- [ ] **Step 3: Filter once at every external boundary**

At `StatsEngine` public collection entry points, normalize inputs before calculation:

```swift
private static func tracked(_ items: [Habit]) -> [Habit] {
    items.filter(\.isTrackedHabit)
}
```

Use `store.activeTrackedHabits` throughout `StatsView`, daily/weekly summary loops, celebration status, Pro active-count checks, graph-widget snapshots, Siri habit selection, and graph/share debug fixtures. Do not change the combined list or reminder scheduler to this filtered property.

- [ ] **Step 4: Run all focused boundary tests**

Expected: reminder completion does not alter statistics, summaries, celebrations, widget graphs, or the free tracked-habit count.

- [ ] **Step 5: Commit the behavior boundary**

```bash
git add Haiity/Models/HabitStore.swift Haiity/Models/StatsEngine.swift \
  Haiity/Models/Celebration.swift Haiity/Views/StatsView.swift \
  Haiity/Views/ContentView.swift HaiityWidget/HaiityWidget.swift \
  HaiityTests/StatsEngineTests.swift HaiityTests/SummaryTests.swift \
  HaiityTests/CelebrationTests.swift HaiityTests/ProGateTests.swift \
  HaiityTests/WidgetLogicTests.swift
git commit -m "Exclude reminders from habit analytics"
```

---

### Task 3: Add the Habit/Reminder Editor Switch

**Files:**
- Modify: `Haiity/Views/EditHabitSheet.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Create: `HaiityTests/ReminderItemTests.swift`

**Interfaces:**
- Consumes: `HabitItemType`.
- Produces: editor state `@State private var itemType: HabitItemType = .habit`.
- Save contract: both new and edited items persist `habit.itemType = itemType`; all other fields follow the existing save path unchanged.

- [ ] **Step 1: Add failing source and save-contract tests**

Verify the editor contains a segmented picker with `item-type-picker`, loads `habit.itemType`, writes it during save, and leaves the existing `recurrenceSection`, `durationSection`, `kindSection`, and `colorSection` in the form.

- [ ] **Step 2: Run `ReminderItemTests` and confirm failure**

Expected: missing editor classification state and picker.

- [ ] **Step 3: Implement the top segmented control**

In the first form section, before the name field:

```swift
Picker(String(localized: "Art"), selection: $itemType) {
    Text(String(localized: "Habit")).tag(HabitItemType.habit)
    Text(String(localized: "Erinnerung")).tag(HabitItemType.reminder)
}
.pickerStyle(.segmented)
.accessibilityIdentifier("item-type-picker")
```

Load and save with:

```swift
itemType = habit.itemType
habit.itemType = itemType
```

Keep one editor and all current fields. The classification affects list presentation and analytics boundaries, not form duplication.

Move the free habit-limit decision to save time for newly created tracked habits so a user at the tracked-habit cap can still create reminders. Present the existing Habits paywall from the editor when saving a new `.habit` would exceed the limit; editing an existing habit never triggers a creation gate.

- [ ] **Step 4: Translate and validate the new visible strings**

Add complete entries for `Art` and `Erinnerung` in all 16 non-source locales. Run:

```bash
jq empty Haiity/Localizable.xcstrings
```

- [ ] **Step 5: Run editor, Pro gate, persistence, and localization tests**

Expected: both item types create and edit through the same form; the tracked-habit cap does not block reminder creation.

- [ ] **Step 6: Commit the editor switch**

```bash
git add Haiity/Views/EditHabitSheet.swift Haiity/Views/ContentView.swift \
  Haiity/Localizable.xcstrings HaiityTests/ReminderItemTests.swift
git commit -m "Add habit and reminder editor switch"
```

---

### Task 4: Render Compact Reminder Rows in the Combined List

**Files:**
- Create: `Haiity/Views/ReminderRow.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/ReminderItemTests.swift`
- Modify: `HaiityTests/SearchFlowTests.swift`
- Modify: `HaiityTests/GesturePerfTests.swift`

**Interfaces:**
- Produces: `ReminderRow(habit:onToggle:onEdit:onArchive:)`.
- Consumes: existing `toggleDay`, `editing`, `store.archive`, `RecurrenceText.summary`, and the single `filteredHabits` ordering.
- Presentation contract: `ContentView.row` branches by `habit.itemType`; only `.habit` constructs `HabitCard`.

- [ ] **Step 1: Write failing row-policy and mixed-search tests**

Add this pure presentation policy and test it directly:

```swift
XCTAssertEqual(ItemPresentation.forItem(reminder), .reminderRow)
XCTAssertEqual(ItemPresentation.forItem(habit), .habitCard)
```

Add source assertions that `ReminderRow.swift` contains no `ContributionGrid`, `Backfill`, `HabitSessionManager`, or `ShareLink`, and that mixed search results retain both item types.

- [ ] **Step 2: Run reminder and search tests and verify failure**

Expected: no reminder-specific row exists.

- [ ] **Step 3: Implement the compact row**

Build a stable native row with a 44-point trailing check control:

```swift
struct ReminderRow: View, Equatable {
    let habit: Habit
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: Theme.Metrics.gap) {
            Text(habit.emoji.isEmpty ? "\u{2022}" : habit.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name).font(.body.weight(.semibold))
                Text(RecurrenceText.summary(habit.recurrence,
                                            timeMinutes: habit.timeMinutes ?? habit.reminderMinutes))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Metrics.gap)
            Button(action: onToggle) {
                Image(systemName: habit.isDone(DayKey.today())
                      ? "checkmark.circle.fill" : "circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("reminder-check-\(habit.id.uuidString)")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button(String(localized: "Bearbeiten"), action: onEdit)
            Button(String(localized: "Archivieren"), role: .destructive, action: onArchive)
        }
    }
}
```

Resolve the fallback symbol with an SF Symbol view rather than the literal bullet in final code. Prevent the row tap gesture from double-firing when the check button is tapped by using button/row hit regions verified in the simulator.

Branch in `ContentView.row` and retain identical list insets, probe behavior, and search redirect behavior. Reminder check-off must call `toggleDay` so undo and notification reconciliation remain centralized.

- [ ] **Step 4: Make search copy inclusive**

Replace habit-only prompt/empty-result wording with German copy that covers Habits and Erinnerungen, then translate each changed key across all locales.

- [ ] **Step 5: Run reminder, search, interaction, and notification reconciliation tests**

Expected: mixed list/search work; reminder check/reset uses the existing log and undo path; HabitCard interaction tests remain unchanged.

- [ ] **Step 6: Commit the combined-list UI**

```bash
git add Haiity/Views/ReminderRow.swift Haiity/Views/ContentView.swift \
  Haiity/Localizable.xcstrings HaiityTests/ReminderItemTests.swift \
  HaiityTests/SearchFlowTests.swift HaiityTests/GesturePerfTests.swift
git commit -m "Show reminders in the habits list"
```

---

### Task 5: Split Apple Calendar Selection by Item Type

**Files:**
- Modify: `Haiity/Services/CalendarSync.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/CalendarSyncTests.swift`
- Modify: `HaiityTests/ProGateTests.swift`
- Modify: `HaiityTests/DiagnosticsTests.swift`

**Interfaces:**
- Produces: `CalendarSync.syncHabits`, `CalendarSync.syncReminders`, and aggregate `CalendarSync.isEnabled`.
- Produces: pure `CalendarSyncSelection.includes(_:) -> Bool` selection policy.
- Keeps: `CalendarSync.reconcile(habits:validate:)`, one EventKit permission, one calendar, one map, and one fingerprint store.

- [ ] **Step 1: Write failing migration and selection tests**

Inject a `UserDefaults` suite into pure preference helpers and verify:

```swift
XCTAssertEqual(migrate(oldEnabled: true), .init(habits: true, reminders: false))
XCTAssertEqual(migrate(oldEnabled: false), .init(habits: false, reminders: false))
XCTAssertEqual(selection(habits: true, reminders: false).includes(tracked), true)
XCTAssertEqual(selection(habits: true, reminders: false).includes(reminder), false)
XCTAssertEqual(selection(habits: false, reminders: true).includes(reminder), true)
```

Test all four toggle combinations and classification changes.

- [ ] **Step 2: Run Calendar and Pro tests and verify failure**

Expected: only the legacy aggregate switch exists.

- [ ] **Step 3: Implement device-local selection with legacy migration**

Add keys and aggregate behavior:

```swift
static let habitsEnabledKey = "calendarSyncHabitsEnabled"
static let remindersEnabledKey = "calendarSyncRemindersEnabled"

static var syncHabits: Bool {
    get {
        if defaults.object(forKey: habitsEnabledKey) == nil {
            return defaults.bool(forKey: enabledKey)
        }
        return defaults.bool(forKey: habitsEnabledKey)
    }
    set { defaults.set(newValue, forKey: habitsEnabledKey) }
}

static var syncReminders: Bool {
    get { defaults.bool(forKey: remindersEnabledKey) }
    set { defaults.set(newValue, forKey: remindersEnabledKey) }
}

static var isEnabled: Bool { syncHabits || syncReminders }
```

Filter active items before plan construction:

```swift
let selected = active.filter {
    $0.isReminder ? syncReminders : syncHabits
}
```

Use the selected set for `seen`; existing map cleanup then removes only events no longer selected and leaves the other type untouched.

- [ ] **Step 4: Replace the More switch with two bindings**

Render `Habits im Kalender` and `Erinnerungen im Kalender`. Each enabling path applies the existing Pro gate and permission request. Each disabling path updates only its flag and immediately calls `reconcile`; when both are off, reconciliation removes all managed events but leaves the calendar.

- [ ] **Step 5: Translate and validate Calendar copy**

Update the footer to describe both item types. Validate JSON and all locale entries.

- [ ] **Step 6: Run Calendar, Pro, diagnostics, and lifecycle tests**

Expected: old enabled users retain Habit events only; all four new combinations pass; diagnostics aggregate remains truthful.

- [ ] **Step 7: Commit the Calendar split**

```bash
git add Haiity/Services/CalendarSync.swift Haiity/Views/MoreView.swift \
  Haiity/Localizable.xcstrings HaiityTests/CalendarSyncTests.swift \
  HaiityTests/ProGateTests.swift HaiityTests/DiagnosticsTests.swift
git commit -m "Split calendar sync by item type"
```

---

### Task 6: Harden Notifications, Sync, and Classification Changes

**Files:**
- Modify: `Haiity/Services/Reminders.swift`
- Modify: `Haiity/Models/HabitStore.swift`
- Modify: `HaiityTests/ReminderUpcomingTests.swift`
- Modify: `HaiityTests/StoreAndMergeTests.swift`
- Modify: `HaiityTests/CloudSyncTests.swift`
- Modify: `HaiityTests/ReminderItemTests.swift`

**Interfaces:**
- Consumes: combined `activeHabits`; reminders intentionally remain eligible for per-item notification plans.
- Produces: explicit tests proving classification has no effect on recurrence/time notification behavior.
- Keeps: current pending-request budget and identifier format.

- [ ] **Step 1: Add notification parity and merge tests**

Create the same scheduled item once as `.habit` and once as `.reminder`; assert equal identifiers/date components/body policy apart from IDs/names. Verify checked, archived, invalid-time, recurrence, and budget behavior for reminders. Verify a newer remote classification wins and repeated merge is idempotent.

- [ ] **Step 2: Run focused tests and inspect failures**

Expected: most notification parity may already pass because the scheduler is shared; any failure identifies an accidental Habit-only filter introduced by earlier tasks.

- [ ] **Step 3: Keep scheduler inclusion explicit**

Name combined scheduler inputs `items` internally where that improves clarity, but preserve public compatibility where broad renaming adds no value. Do not filter `habitPlans` to tracked habits. Ensure external check-off removes today's request for either item type.

- [ ] **Step 4: Run notification, store, cloud, and full summary suites**

Expected: reminders schedule normally but never enter summary plans; the 64-request cap passes for mixed lists with motivation both on and off.

- [ ] **Step 5: Commit scheduler hardening**

```bash
git add Haiity/Services/Reminders.swift Haiity/Models/HabitStore.swift \
  HaiityTests/ReminderUpcomingTests.swift HaiityTests/StoreAndMergeTests.swift \
  HaiityTests/CloudSyncTests.swift HaiityTests/ReminderItemTests.swift
git commit -m "Harden reminder scheduling and sync"
```

---

### Task 7: Full Localization, Visual Verification, and Release Gate

**Files:**
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `tools/release.sh`
- Test: all `HaiityTests`

**Interfaces:**
- Consumes: completed combined-item behavior.
- Produces: measured test floor and verified light/dark screenshots.

- [ ] **Step 1: Validate catalog completeness mechanically**

Run `jq empty`, compare new keys against `HEAD`/the feature baseline, and verify every new visible key has 16 translated non-source locales with matching format placeholders.

- [ ] **Step 2: Run focused feature suites**

Run `ReminderItemTests`, `CalendarEventPlanTests`, `ReminderUpcomingTests`, all Summary classes, `StatsEngineTests`, `ProGateTests`, `WidgetLogicTests`, `SearchFlowTests`, and `DiagnosticsTests` on the stable-Xcode simulator.

Expected: zero failures.

- [ ] **Step 3: Run the complete stable-Xcode test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=haiity-v6' \
  -only-testing:HaiityTests -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO
```

Capture the exact executed test count and update `MIN_TESTS` in `tools/release.sh` to that count.

- [ ] **Step 4: Install and inspect the app in light mode**

Create one Habit and one Erinnerung. Capture the combined list, the editor segmented control, mixed search results, and both Calendar toggles. Verify the reminder row has no graph and its checkmark does not trigger row editing.

- [ ] **Step 5: Repeat visual inspection in dark mode and large Dynamic Type**

Verify no clipping, overlap, nested cards, or inaccessible hit targets. Test an RTL locale for native row/checkmark direction and swipe behavior.

- [ ] **Step 6: Exercise actual Calendar and notification behavior**

With permission granted, test all four Calendar toggle combinations in Apple Calendar and verify stale events are removed without duplicate alarms. Schedule a near-future reminder, check it before fire time, and confirm today's pending request disappears.

- [ ] **Step 7: Run repository hygiene checks**

```bash
jq empty Haiity/Localizable.xcstrings
git diff --check
git status --short
```

Review the complete diff for privacy, iCloud compatibility, EventKit cleanup, notification budget, and generated metadata churn.

- [ ] **Step 8: Commit verification metadata**

```bash
git add Haiity/Localizable.xcstrings tools/release.sh
git commit -m "Verify combined habits and reminders"
```

- [ ] **Step 9: Push only after all verification is fresh**

Push `feature/navigation-card-interactions`. Do not bump or upload another TestFlight build unless explicitly continuing into a release after this implementation.
