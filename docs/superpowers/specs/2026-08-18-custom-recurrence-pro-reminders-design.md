# Custom One-Time Reminders and Pro Reminders Sync

## Scope

This change covers two related product rules:

1. The recurrence editor gets a `Custom` option before `Täglich`. `Custom`
   selects one calendar day and creates a one-time `Erinnerung` automatically.
2. Syncing hAiity reminders into Apple Reminders remains a Pro-only feature,
   with the entitlement boundary represented and tested explicitly.

The existing end-date and end-count controls remain available for recurring
habits and reminders, but their obsolete `Kategorie / Endtitel` input is
removed from the editor.

## Recurrence Model

Add `Recurrence.Frequency.once` as a first-class frequency. Its `start` value
is the only scheduled day. The normalized rule has no interval, weekday,
month, flexible target, or end condition. Existing persisted recurrence data
continues to decode unchanged; existing `endTitle` data remains readable for
backward compatibility but is no longer exposed or written by the current
editor.

The schedule engine must treat `.once` consistently for `isScheduled`,
`occurrences`, and `nextOccurrence`. A date before the selected day has that
day as its next occurrence; the selected day is the only occurrence; later
dates have no next occurrence. Invalid or missing dates produce no scheduled
occurrence rather than a recurring fallback.

## Editor Flow

The frequency segmented control order is:

`Custom | Täglich | Wöchentlich | Monatlich | Jährlich`

When `Custom` is selected, the editor displays a native compact date picker
for the one-time date. Selecting the frequency automatically sets the item
type to `Erinnerung`, clears the end mode to `Nie`, and hides recurring-only
controls such as interval, weekday, month, start toggle, and end controls.
The existing Habit/Erinnerung picker remains available so the user can see and
change the item type, but the automatic default is always `Erinnerung` for a
custom one-time entry.

The end section continues to show `Nie`, `Am Datum`, and `Nach Anzahl` for
recurring frequencies. It no longer renders a category/end-title text field
for either finite end mode. The existing end-title model and native Calendar
title behavior remain compatible for data that was created before this change;
new editor saves pass no end title.

## Calendar and Apple Reminders

`CalendarEventPlan` maps `.once` to a single native event without an
`EKRecurrenceRule`; the event date is the selected day and existing per-item
calendar opt-out behavior is unchanged.

The Apple Reminders sync toggle uses the same `CalendarFeatureGate` as Apple
Calendar. Enabling either native calendar feature requires `Pro.isUnlocked`;
disabling remains available after an entitlement is lost. The sync service
continues owning only the hAiity list and only hAiity-created reminders.

## Data Flow and Compatibility

1. The editor maps `Custom` to a `.once` draft.
2. Saving persists the `.once` recurrence and `HabitItemType.reminder`.
3. Habit occurrence, notification, Calendar, widget, and Apple Reminders code
   consume the shared schedule APIs rather than special-casing UI state.
4. Existing recurrence JSON remains decodable. The new frequency gets a stable
   Codable value, and legacy forms retain their current migration behavior.
5. Changing a one-time reminder back to a recurring frequency restores the
   recurring editor controls without carrying over the one-time end state.

## Error Handling

- A malformed one-time date is treated as unscheduled and is never silently
  converted into a daily rule.
- Calendar and Apple Reminders permission failures preserve the existing
  denied-state UI and do not enable sync.
- Pro gating must happen before requesting native permission or writing native
  items.

## Verification

Add or update focused tests for:

- `.once` schedule matching, occurrence enumeration, next-occurrence behavior,
  Codable round-trip, and malformed input.
- Draft round-trip and automatic reminder behavior for `Custom`.
- The editor contract: custom control exists and `end-title` no longer does.
- Calendar plans creating one non-repeating event for `.once`.
- Apple Reminders and Calendar enable paths both requiring Pro, while disable
  remains free.
- The existing `$9.99` non-consumable StoreKit product remains unchanged; no
  subscription product is introduced by this feature.

## Non-Goals

- No new subscription or lifetime product is added.
- No redesign of the recurrence editor outside the requested Custom option and
  end-title removal.
- No change to the ownership, list naming, or bidirectional completion rules
  for Apple Reminders sync.
