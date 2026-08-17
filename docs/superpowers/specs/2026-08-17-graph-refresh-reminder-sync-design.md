# Graph Widget, GitHub Refresh, and Apple Reminders Sync

## Scope

This change fixes the GitHub graph widget configuration, makes GitHub refresh
feedback visible, and adds two-way synchronization for hAiity reminder items
with Apple Reminders. Existing tracked-habit/calendar sync remains unchanged.

The native Reminders integration owns only a dedicated `hAiity` list. It never
imports, matches, or edits unrelated Apple Reminders.

## Design

### 1. Graph widget configuration

`SelectGraphIntent` remains the single configuration intent for the pure graph
widget. Its source parameter exposes `Habit` and `GitHub`. The habit parameter
is dependent on the source, so it is shown only for a habit graph. The default
source remains deterministic, while an explicit GitHub selection always takes
precedence over a habit selection.

The widget receives a palette selection as an AppEntity rather than a fixed
enum. The query returns:

- the six built-in graph palettes;
- every custom palette in the shared `HabitData.customPalettes` collection.

The entity ID stores the existing `PaletteRef.rawValue`, which gives built-in
and custom palettes one stable representation and lets a deleted custom
palette fall back through the existing palette resolution chain. The widget
entry carries the selected `PaletteRef` and resolves it from the same
`PaletteBook` used by the app. If no palette is selected, the existing habit
palette/global palette behavior remains the fallback.

Both habit and GitHub graph rendering use the resolved style. The GitHub graph
no longer hard-codes `PaletteStyle.default`.

### 2. GitHub refresh feedback

`GitHubContributionStore` keeps connection phase and refresh activity as
separate concerns:

- `isRefreshing` is true only while a forced or scheduled fetch is running;
- a refresh result records success or the user-facing failure message;
- a concurrent refresh request joins the existing task instead of starting a
  second network request.

`GitHubSettingsView` disables the refresh command while active, shows a
progress indicator, and animates a checkmark response on success. Failures are
shown in the same section without discarding a valid cached snapshot. A
successful forced refresh persists the shared snapshot and reloads the graph
widget timeline, as it does today.

### 3. Apple Reminders synchronization

`ReminderSync` is a separate `@MainActor` EventKit service. It has its own
permission check, list identifier, reminder ID map, fingerprints, and
preference key. It does not reuse calendar-event identifiers or calendar
authorization state.

The service maintains one list titled `hAiity` using `EKEntityType.reminder`.
For each active hAiity reminder whose per-item calendar/reminder setting and
global native-reminder toggle are enabled, it stores:

- the hAiity habit UUID;
- the native reminder identifier;
- a fingerprint of title, due date, recurrence, and end rule.

Reconciliation is idempotent:

- missing owned reminders are created in the hAiity list;
- changed plans replace the owned reminder and update the fingerprint;
- archived, deleted, disabled, or no-longer-plannable hAiity reminders are
  removed from the hAiity list;
- external reminders and lists are never queried for title matches or edited.

The existing Pro gate applies to enabling the native Reminders toggle. Turning
it off remains free and removes only hAiity-owned native reminders. The native
Reminders permission is requested only after the user actively enables the
toggle. `NSRemindersFullAccessUsageDescription` is added to the app bundle.

Completion synchronization uses the owned ID map and the reminder’s current
actionable occurrence:

- completing or reverting an hAiity reminder sets the corresponding native
  reminder’s `isCompleted` state;
- an external native completion or revert updates the corresponding hAiity
  occurrence through `HabitStore.setReminderCompletion`;
- a change observer on `EKEventStoreChanged` triggers a guarded pull and
  reconcile;
- an in-flight/source-generation guard prevents app writes from being echoed
  back as an infinite native-to-app loop.

The hAiity data remains authoritative for title, schedule, and history. Native
completion is authoritative only for the current mirrored occurrence. If an
owned native reminder is deleted, the hAiity item and its history remain, and
the next reconcile recreates the mirror.

### 4. Settings placement

The native Reminders toggle appears beside the existing calendar toggles in
`Habit behaviour`. It uses the existing Pro purchase context and adds a
separate permission hint for Reminders when access is denied. The existing
calendar toggles keep their current behavior and wording.

### 5. Testing and verification

Pure tests cover:

- graph source and palette entity IDs, built-in/custom query results, and
  deleted-custom fallback;
- selected palette propagation into habit and GitHub widget entries;
- refresh state transitions, forced fetch behavior, success, failure, and
  widget reload trigger;
- reminder plan fingerprints, ownership filtering, completion mapping, and
  preference migration.

Source-contract tests cover the AppIntent dependency, settings identifiers,
permission usage description, and the refresh feedback controls. The full
suite must pass, followed by a stable-Xcode debug simulator build. A simulator
check will verify the graph widget renderer with a GitHub snapshot and a
custom palette, the refresh success response, and the native reminder toggle
state when EventKit permission is unavailable.

## Error handling and compatibility

- Existing `HabitData` and `PaletteRef` formats remain backward compatible.
- A missing or deleted custom palette falls back to the global/default style.
- A missing token or failed GitHub fetch preserves a valid cached graph.
- Denied Reminders access leaves the toggle off and provides a path to iOS
  Settings; no partial native data is created.
- Missing native IDs never delete hAiity data.

## Out of scope

- importing unrelated Apple Reminders into hAiity;
- syncing tracked habits into Apple Reminders;
- replacing the existing Apple Calendar event mirror;
- adding custom palette editing to the widget editor itself.
