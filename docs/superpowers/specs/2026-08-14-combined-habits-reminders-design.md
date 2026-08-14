# Combined Habits and Reminders

Date: 2026-08-14
Status: Approved design

## Objective

Add lightweight reminder items to the existing Habits experience without
creating another page or another scheduling system. A reminder is created and
scheduled like a habit, appears in the same list, and can be checked off for
the current day. Its visible difference is that it has no contribution graph
or habit statistics.

## Product Structure

The primary navigation remains unchanged:

```text
[ Statistik | Habits | Mehr ]                 [ Suchen ]
```

- `Statistik` continues to show tracked habit performance.
- `Habits` becomes the combined list of habits and reminders.
- `Mehr` continues to contain app settings and Calendar sync controls.
- The native Search-role tab/button remains separate on the right.
- There is no Reminder tab, reminder page, or reminder-only navigation state.

Search, sorting, archive, iCloud sync, import, and export operate across both
item types. Existing deep links continue to open the Habits page.

## Data Model

Add a codable item classification to `Habit`:

```swift
enum HabitItemType: String, Codable, CaseIterable, Sendable {
    case habit
    case reminder
}
```

`Habit.itemType` defaults to `.habit`. Decoding an existing file without the
field produces `.habit`, so every shipped item keeps its current behavior.
Encoding and all targets that compile `Habit` use the same definition.

This is deliberately not a new `HabitKind` case. `HabitKind` describes how a
tracked item is answered (`checkbox`, `quantity`, or `yesNo`); `HabitItemType`
describes whether the item has habit analytics and a graph. It is also not a
separate Reminder model because recurrence, time, daily completion, archive,
iCloud merge, and Calendar sync would otherwise be duplicated.

Changing an existing item between Habit and Reminder keeps its identifier,
name, emoji, recurrence, time, completion log, archive state, palette, and
other saved configuration. Returning it to Habit therefore restores its graph
and historical data. Reminder presentation simply does not expose that graph.

## Create and Edit

The existing create/edit form gains a segmented control at the top of the
first section:

```text
[ Habit | Erinnerung ]
Name
Emoji
```

- New items default to `Habit`.
- Editing shows the item's saved classification.
- The rest of the form remains the existing form. Name, emoji, recurrence,
  start date, time, duration, response kind, color, archive, and other current
  controls are not reimplemented in a reminder-specific editor.
- The existing `Uhrzeit` behavior remains the notification time for either
  classification.
- The create action and presentation animation remain unchanged.
- German interface copy uses `Habit` and `Erinnerung`.

## Combined List

Habits keep the existing `HabitCard`, including graph, today's response,
context actions, swipe actions, and graph interactions.

Reminders use a dedicated compact row in the same `List` and ordering:

- Leading emoji when present; otherwise a familiar reminder/checklist symbol.
- Name as the primary label.
- Schedule/time as secondary text when useful.
- One trailing checkmark control for today's state.
- Checked state remains visibly distinct but does not remove the reminder from
  the list before the next due day.
- Tapping the row opens the existing edit sheet.
- Swipe completion and reset use the existing mutation/undo path where those
  actions apply.
- Long press exposes edit and archive commands, without graph preview,
  Nacharbeiten, sharing a contribution graph, or session presentation.
- The row maintains a stable minimum 44-point hit target and supports Dynamic
  Type and VoiceOver.

Reminder rows do not show a graph, streak, percentage, quantity progress,
timer, Live Activity entry point, or backfill calendar. They do not contribute
to `StatsEngine`, daily/weekly habit summaries, perfect-day celebration, habit
limits, or graph-derived widgets. Their daily log is retained only to answer
whether that reminder was checked for a scheduled day and to support sync.

The empty state distinguishes a completely empty list from a list containing
only one item type. The main create button always opens the shared form, where
the segmented control chooses the type.

## Notifications

Reminder items reuse the concrete per-item notification scheduler already used
by habits:

- A reminder with `Uhrzeit` schedules a notification only on dates allowed by
  its recurrence.
- Checking it before its time removes today's pending notification.
- Archived reminders schedule nothing.
- Saving, changing recurrence/time/type, restoring, importing, merging, and
  launching or activating the app reconcile pending requests.
- Notification identifiers continue to use the stable item ID and due day.
- Daily motivation, daily summary, weekly summary, session milestone, and
  celebration requests remain separate and preserve the 64-request budget.

The notification title uses the reminder's emoji/name in the same way as a
habit notification. No Apple Reminders integration is added; the native
integration in this scope is Apple Calendar through EventKit.

## Apple Calendar

The existing single `Habits im Kalender` switch becomes two independent,
device-local switches in the same Calendar section:

- `Habits im Kalender`
- `Erinnerungen im Kalender`

Both share the existing EventKit full-access permission, Pro entitlement, one
private `hAiity` calendar, event map, and reconciliation engine.

- Enabling either switch requests access only when needed and reconciles the
  selected type.
- Each item type is included only when its own switch is enabled.
- Turning off one switch removes only that type's future events.
- Turning off both removes all managed events while leaving the empty hAiity
  calendar itself intact, matching current behavior.
- Existing installations with `calendarSyncEnabled == true` migrate to Habits
  enabled and Reminders disabled. This preserves every existing event and does
  not introduce new reminder events without an explicit user choice.
- Calendar event titles, recurrence, time, duration, URL, and no-duplicate-
  alarm policy continue to use `CalendarEventPlan`.
- Event bookkeeping keys include the stable item ID; classification changes
  reconcile by removing the old type's event when disabled and creating the
  new type's event when enabled.

## Sorting and Search

- The combined list follows the current user-selected sort for both types.
- Manual/default ordering remains based on the single stored item array.
- Search matches names and shows the same card/row presentation as the main
  list.
- Search copy changes from habit-only wording to inclusive item wording where
  necessary.
- Statistics continue to filter to `itemType == .habit` before applying
  existing statistics logic.

## Sync, Import, and Compatibility

- `itemType` participates in JSON export/import and the existing newer-metadata
  iCloud merge rule.
- Missing or unknown values decode safely as `.habit`; a malformed item type
  must not make the whole data file unreadable.
- App and widget targets remain model-compatible.
- Existing reminder notification times in `timeMinutes` and legacy
  `reminderMinutes` remain readable and mirrored according to current rules.
- Permanent deletion and archive semantics remain unchanged.
- No server, account, remote notification, or Apple Reminders entitlement is
  introduced.

## Error Handling

- Denied notification access retains the chosen time and uses the existing
  route to iOS notification settings.
- Denied Calendar access leaves both requested toggles off and displays the
  existing settings link.
- EventKit failures preserve local reminder/habit data and remain retryable on
  the next reconciliation.
- If a stored Calendar event is manually deleted, validated reconciliation
  recreates it only when that item's type toggle is enabled.

## Localization and Accessibility

All new interface strings are translated for every currently supported
locale. The segmented item-type control, reminder checkmark, Calendar toggles,
search results, edit action, and archive action receive stable accessibility
labels/identifiers. Right-to-left layouts keep checkmark placement and swipe
semantics native.

## Verification

### Unit Tests

- Existing files decode every item as `.habit`; reminder type round-trips and
  merges without changing completion history.
- Classification changes preserve all shared fields.
- Habit-only analytics, summaries, celebration, limits, widgets, graph, and
  backfill inputs exclude reminders.
- Reminder rows resolve today's scheduled/checked state correctly.
- Reminder notifications respect recurrence, time, completion, archive, and
  the existing pending-request budget.
- Calendar migration preserves the old Habits-enabled state and leaves
  Reminders disabled.
- Every Calendar toggle combination filters plans correctly and disabling one
  type removes only that type's events.
- Sorting, search, archive, import/export, and iCloud merge cover mixed lists.

### UI and Device Verification

- Create and edit both item types in light/dark mode and at large Dynamic Type.
- Switch an existing item both directions and confirm history is restored when
  returning to Habit.
- Check and reset a reminder from its row and from search.
- Confirm reminder rows have no graph/context preview and habit cards are
  unchanged.
- Confirm Statistik remains unchanged with mixed data.
- Verify Search remains the separate native right-side role on iOS 26/27 and
  the fallback navigation remains unchanged on older supported iOS versions.
- Exercise denied/allowed notification and Calendar permissions.
- Inspect Apple Calendar for all four Habits/Reminders toggle combinations and
  confirm there are no duplicate alarms or stale events.
- Run the complete stable-Xcode release gate and inspect screenshots rather
  than inferring UI correctness from source.

## Out of Scope

- A separate Reminder page or navigation tab.
- Apple Reminders app integration.
- One-off reminder-only data models or stores.
- Reminder graphs, streaks, statistics, backfill, sessions, or Live Activities.
- Reminder-specific colors, icons, or a second create flow.
- Changes to the native Search-role placement or primary navigation layout.
