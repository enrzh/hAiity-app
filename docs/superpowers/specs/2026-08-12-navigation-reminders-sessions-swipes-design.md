# hAiity Navigation, Reminders, Sessions, and Swipes

Date: 2026-08-12
Status: Approved design

## Objective

Make hAiity's primary navigation easier to discover, simplify each habit card,
restore configurable swipe actions, add useful per-habit reminders, and retain
exact completed-session history for future time-based statistics. Strengthen
the GitHub-grid character without sacrificing native iOS behavior,
localization, accessibility, or readability.

## Scope

This work includes:

- A bottom Habits/Mehr navigation group with a separate create button.
- A cleaner habit-card header without the ellipsis button.
- Long-press graph preview leading directly to Bearbeiten.
- Per-habit scheduled reminders.
- Planned-duration milestone notifications for active sessions.
- Permanent history for finished sessions with exact timestamps.
- Global swipe defaults with optional per-habit overrides.
- Restrained blocky/monospaced visual polish.

This work does not include new statistics screens, automatic session
completion, persistent cancelled-session history, remote notifications, a
custom navigation-bar implementation, or a third-party display-font
dependency.

## Navigation

### iOS 27 and later

The bottom navigation has two native destinations in a left-side group and a
separate prominent create action on the right:

```text
[ Habits | Mehr ]                         [ + ]
```

- `Habits` shows the current habits list and search interface.
- `Mehr` shows `MoreView` as a normal tab rather than a full-screen cover.
- Each tab preserves its own navigation state while switching tabs.
- The create button opens the existing create-habit page and remains visually
  separate from the navigation group.
- The top three-dot menu is removed. Search remains in the Habits toolbar.
- Deep links to `more`, `stats`, `archive`, and related routes select Mehr and
  then present or navigate to the requested destination.

Use native `TabView` APIs available in the release iOS 27 SDK, including the
native prominent action role if it produces the required split layout. Remove
the temporary custom iOS 27 create-circle implementation once the native role
is available in the shipping toolchain.

### iOS 26

Use the closest stable native layout supported by the release SDK. Preserve
Habits and Mehr as real destinations and keep create as a separate action. Do
not reintroduce the old search-role workaround if it causes search activation
or incorrect tab semantics.

### iOS 17 through 25

Extend the existing fallback bottom chrome to expose Habits and Mehr on the
left and create on the right. Behavior and accessibility labels must match the
newer native implementations.

## Habit Card Interaction

- Remove the ellipsis button from the card header.
- Tapping an individual graph cell continues to open Nacharbeiten at that
  date. It never writes immediately.
- Long-pressing the graph presents the existing enlarged graph preview and
  context menu.
- Tapping the enlarged preview dismisses the context presentation and opens
  Bearbeiten for that habit.
- The context menu retains secondary commands that are still useful from the
  graph: Nacharbeiten, start/finish-related session commands, share, edit, and
  archive as appropriate.
- Header controls such as today's completion button retain their current
  behavior and hit targets.

If SwiftUI does not reliably deliver a tap from a context-menu preview, use a
clearly labeled `Bearbeiten` action as the guaranteed path and treat preview
tapping as progressive enhancement. Do not replace the system context-menu
interaction with a fully custom gesture layer solely to force this behavior.

## Per-Habit Reminders

`Habit.reminderMinutes` becomes user-facing again in Bearbeiten and during
habit creation:

- A reminder toggle controls whether the habit has its own notification.
- Enabling it reveals a time picker.
- Permission is requested only when the user enables a reminder or explicitly
  enables notifications in the existing setup flow.
- Denied permission leaves the selected time stored and shows the existing
  route to iOS notification settings.
- A reminder is scheduled only for dates on which the habit's recurrence says
  it is due and it has not already been completed. A check-in reconciles the
  affected habit's pending request so completing early does not produce a
  redundant reminder later that day.
- Archived habits never schedule reminders.
- Saving, importing, merging, archiving, restoring, or deleting relevant data
  causes local reminder plans to be reconciled.
- Daily and weekly summaries remain independent features and schedules.

### Scheduling Strategy

iOS limits pending local notifications. Use a rolling window of concrete,
date-based notification requests rather than an unbounded request per future
occurrence. Reconcile the window when the app launches, becomes active, or
habit/reminder data changes. Request identifiers contain the habit ID and due
day so stale requests can be replaced without touching summary or session
notifications.

Notification content identifies the habit by emoji/name and opens the Habits
tab. A future enhancement may add direct completion actions, but they are not
part of this scope.

## Timed Sessions

### Runtime Behavior

- Starting a session records the exact `startedAt` timestamp and the planned
  duration as it existed at start.
- The Live Activity displays elapsed time as a count-up for the entire
  session. A planned duration drives its progress indicator and target label,
  but the main timer never freezes at zero.
- At the planned end, hAiity sends one local milestone notification stating
  that the target duration has been reached.
- Reaching the target does not finish the session, mark the habit complete, or
  stop the clock.
- The elapsed timer and Live Activity continue until the user chooses Finish
  or Cancel. No background UI-state transition is required at the milestone.
- Finish records the exact end timestamp, credits completion through the
  existing check-off path, updates backward-compatible daily duration data,
  clears the active session, cancels its milestone request, and ends the Live
  Activity.
- Cancel clears the active session, cancels its milestone request, and ends
  the Live Activity without adding permanent history or completion data.
- Starting a different session continues the current single-active-session
  rule: the previous active session is cancelled, not silently completed.

### Persistent Session History

Add a compact codable record for finished sessions containing:

- Stable session ID.
- Habit ID.
- Credited day (the day on which the session started).
- Exact start timestamp.
- Exact finish timestamp.
- Planned duration at start, if any.

Only finished sessions enter permanent history. Cancelled or stale sessions
are discarded. Existing files without session history decode to an empty
collection. Session history participates in export/import and iCloud merge.
Records merge by stable session ID; merging must be idempotent and must not
double-add legacy daily minute totals.

The current per-day minute values remain readable and maintained for existing
UI and backward compatibility. Future statistics should derive richer values
from session records where available, while historical days predating this
feature continue to use aggregate minute data.

## Swipe Actions

### Defaults

Swipe actions are enabled by default and map semantically by habit type:

| Direction | Checkbox | Quantity | Yes/No |
| --- | --- | --- | --- |
| Right/leading | Done | +1 | Yes |
| Left/trailing | Reset today | Reset today | No |

- Every write passes through the existing mutation and undo-toast paths.
- Archive is never a full-swipe action.
- Swipe actions are disabled while another interaction layer, such as
  Nacharbeiten, is active.
- Accessibility exposes equivalent named actions without requiring a swipe.

### Configuration

Mehr contains:

- A master toggle for habit-card swipe actions.
- Global leading and trailing action pickers.
- Type-aware choices that cannot produce an invalid action for a habit kind.

Bearbeiten contains:

- `Globale Einstellung verwenden` by default.
- An optional per-habit override for leading and trailing actions.
- A preview/summary of the effective mapping.

Global preferences belong to the existing syncable `ViewPreferences` value.
Per-habit overrides belong to `Habit`. Old files containing the previous
`leadingSwipe` and `trailingSwipe` keys continue to decode safely; the removed
legacy values are not silently revived as new preferences.

## Visual Direction

The app keeps native navigation glass, familiar SF Symbols, and readable form
typography. The GitHub-grid character is strengthened selectively:

- Use the system monospaced design for timers, streaks, counts, graph labels,
  and compact statistical values.
- Apply a blockier system-supported display treatment only to short headings
  where localization and Dynamic Type remain legible.
- Keep body text, forms, notification settings, and long translated strings in
  the normal system design.
- Reduce decorative circular/pill backgrounds where they do not communicate a
  native control or state.
- Keep required rounded native controls and minimum 44-point hit targets.
- Do not add a Minecraft-style third-party font in this phase. Reconsider only
  after testing glyph coverage for all 16 localizations and accessibility
  sizes.

## Data and Migration

- All new fields decode with backward-compatible defaults.
- Encoding omits default/empty optional values where the project already uses
  that convention.
- iCloud merge rules are deterministic and timestamped where user-editable
  preferences can conflict.
- Importing the same session history repeatedly is idempotent.
- Deleting a habit follows the project's existing archive/delete semantics;
  completed session history remains associated while archived and is removed
  only when the habit is permanently deleted.
- Release builds keep app and widget model definitions compatible wherever a
  shared `HabitData` or `Habit` type is compiled into both targets.

## Verification

### Unit Tests

- Reminder-plan generation respects recurrence, archive state, time, rolling
  window, and notification identifiers.
- Reminder reconciliation does not remove daily/weekly summaries or active
  session milestone requests.
- Planned-end math and milestone identifiers are deterministic.
- Finish stores exact timestamps once, updates completion and daily duration,
  and remains idempotent across repeated intent delivery.
- Cancel and stale cleanup store no history.
- Session-history decoding and iCloud/import merging are backward compatible
  and idempotent.
- Swipe defaults resolve correctly for every habit kind.
- Global and per-habit overrides resolve and migrate correctly.
- Deep links select the correct bottom tab and destination.

### UI and Device Verification

- Habits/Mehr/create layout on iOS 27, iOS 26, and the legacy fallback.
- Search opens and closes repeatedly without create or tab switching
  activating it.
- Mehr retains its navigation state when switching tabs.
- Graph cell tap, graph long press, preview-to-edit path, and context commands
  do not steal one another's gestures.
- Leading/trailing partial and full swipes work in left-to-right and
  right-to-left locales and show undo.
- Notification permission denied, allowed, and provisional states.
- Planned-duration notification fires while the timer and Live Activity keep
  counting, including with the app backgrounded.
- Finish from the Live Activity writes one completed session and ends the
  activity.
- Typography remains readable in all supported localization scripts and
  accessibility text sizes.

Run the repository's complete release gate with the release Xcode. Use beta
Xcode only for OS-specific behavioral testing until the release toolchain can
compile the final iOS 27 APIs.

## Implementation Order

1. Navigation and habit-card interaction cleanup.
2. Per-habit reminder UI and rolling scheduler.
3. Exact session history and planned-duration milestone notification.
4. Global and per-habit swipe configuration.
5. Restrained typography and shape polish.

Each phase should preserve a passing release test gate before the next begins.
