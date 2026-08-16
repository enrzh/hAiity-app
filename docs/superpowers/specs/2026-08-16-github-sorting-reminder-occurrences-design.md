# GitHub Access, Sorting Completion, and Reminder Occurrences

## Scope

This change fixes three related interaction gaps without introducing new top-level pages:

1. Make GitHub connection and disconnection directly discoverable on the main More page.
2. Replace habit creation with a native Done action while sorting is active.
3. Treat recurring reminders as dated occurrences so the list can show actionable dates, confirm early completion, and retain unfinished occurrences.

The existing GitHub account store, habit edit mode, recurrence rules, reminder notification settings, and habit log remain the sources of truth for their respective concerns.

## GitHub On The More Page

Add a `GitHub` row to the main More list near the account and Pro controls.

- When disconnected, the row shows `Verbinden`. Activating it opens the existing GitHub connection view.
- When connected, the row shows the GitHub username and a direct `Abmelden` action.
- Activating the connected row opens the existing GitHub settings view for refresh and account details.
- Disconnect uses the existing `GitHubContributionStore` lifecycle. There is no second connection state in `MoreView`.
- The existing GitHub entry under About and Privacy is removed to avoid duplicate navigation.

The contribution card remains on the Habits page and appears only when a valid GitHub account snapshot is available.

## Sorting Toolbar

The existing trailing toolbar position has two mutually exclusive states:

- Normal: native `plus` icon, accessibility label `Habit erstellen`, opens creation.
- Sorting: native `checkmark` icon, accessibility label `Fertig`, sets edit mode to inactive.

The checkmark does not open the creation sheet. Leaving the page, opening search, or otherwise ending sorting returns the toolbar to the plus state.

## Reminder Occurrence Model

A reminder occurrence is identified by the reminder ID and its scheduled local date and time. Occurrences are derived from the existing recurrence schedule; they are not stored as separate reminder objects.

Completion continues to use the reminder's existing log, keyed to the scheduled occurrence date rather than the moment the user tapped Done. This preserves existing persistence and sync behavior while allowing early and late completion to refer to the correct occurrence.

Existing reminders default to continuing their schedule while unfinished. Existing completion history remains valid and requires no destructive migration.

## Unfinished Recurrence Policy

Reminder editing gains a compact toggle:

- Label: `Trotz offenem Termin wiederholen`
- Default: enabled
- Availability: reminders only

When enabled:

- Every scheduled occurrence becomes independently actionable.
- Unfinished past occurrences remain overdue.
- New occurrences continue according to the recurrence rule.
- The row prioritizes the oldest unfinished occurrence.
- If more overdue occurrences exist, the row shows their count compactly.

When disabled:

- Only one occurrence can remain actionable.
- An unfinished occurrence stays overdue and later schedule slots do not create a backlog.
- Completing that overdue occurrence advances to the first scheduled occurrence after the current time, skipping missed slots.

The notification planner uses the same policy. With continuation enabled it may schedule future occurrences normally. With continuation disabled it schedules only the current actionable occurrence and plans the next one after completion or the next app refresh.

## Reminder Row And Completion

The recurrence description such as `Wöchentlich` is removed from reminder rows. The subtitle describes the actionable occurrence:

- Future today: `Heute, 18:00`
- Future tomorrow: `Morgen, 09:00`
- Later: localized date and time
- Past: `Überfällig · <localized date and time>`

If multiple overdue occurrences exist, a compact suffix reports the additional count without replacing the actionable date.

Tapping Done or using the Done swipe before the selected occurrence's scheduled instant presents a confirmation. Confirming records that scheduled occurrence as complete and advances the row. Cancelling changes nothing.

At or after the scheduled instant, Done completes immediately. Revert remains immediate and reopens the most recently completed relevant occurrence.

The existing reminder swipe directions and visual treatment remain unchanged apart from using occurrence-aware completion.

## Error Handling And Boundaries

- If GitHub authorization data is missing or invalid, the existing GitHub settings view presents its current recovery state.
- If no future recurrence can be calculated, the reminder row uses a neutral `Kein weiterer Termin` state and does not offer early completion.
- Calendar and timezone calculations use the app's injected calendar so daylight-saving changes and tests are deterministic.
- The change does not add a second reminder system, a second GitHub store, or a dedicated reminders page.

## Verification

Automated coverage will verify:

- disconnected and connected GitHub rows, including disconnect;
- plus-to-checkmark toolbar state and Done behavior;
- today, tomorrow, later, and overdue reminder labels;
- early-completion confirmation through tap and swipe;
- immediate due and overdue completion;
- occurrence-keyed completion and revert;
- continuation-enabled backlog behavior;
- continuation-disabled skip behavior;
- decoding existing reminders with the enabled default;
- notification planning under both recurrence policies.

The app will be built and run in an iOS simulator. Screenshots will be inspected for the More row, sorting toolbar, normal reminder date, early-completion confirmation, and overdue reminder states before the UI is reported as verified.
