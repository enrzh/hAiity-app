# Native Entry Categories

## Goal

Make native entries created by hAiity easy to identify, set up, and delete manually by separating habit and reminder entries into dedicated native containers. Keep cleanup ownership reliable across reinstalls, renamed containers, and legacy entries.

## Current State

- Calendar events for both habits and reminders use one calendar named `hAiity`.
- Native Apple Reminders use one list named `hAiity`.
- Each current item stores an invisible `SyncWatermark` in `notes`, containing its item kind and hAiity UUID.
- Calendar events also use `haiity://habits` as their app URL.
- Stored native IDs and fingerprints are device-local and can be lost on reinstall.
- Cleanup already scans for current markers and the exact legacy `hAiity` note without touching arbitrary user content.

## Native Organization

Calendar receives two dedicated calendars:

- `hAiity Habits` receives habit events.
- `hAiity Reminders` receives reminder events.

Apple Reminders receives one dedicated list:

- `hAiity Reminders` receives app reminder items only.
- Habit items are not copied into Apple Reminders.

The names are stable and intentionally independent of the app language so setup and cleanup can find the same containers across locales. A user may rename a container; the stored native identifier remains authoritative while it exists.

## Ownership and Persistence

Keep `SyncWatermark` as the source of truth for ownership. The existing invisible kind values already distinguish habit-calendar, reminder-calendar, and native-reminder entries, so no new visible title prefix or note format is needed.

Replace the single stored Calendar container identifier with identifiers keyed by calendar category. Keep the existing per-habit event map and fingerprints, because native item identifiers remain unique and the watermark still resolves ownership after an app reinstall. Store the native Reminders list identifier under the new dedicated-list key while retaining compatibility with the existing stored key during migration.

All writes continue to use the existing fingerprint and canonical-item logic. A change in habit type routes the item to the other category container and removes the old owned event before creating the replacement.

## Migration and Setup

On the first reconciliation after the update:

1. Inspect all accessible Calendar events and Apple Reminders, not only the new containers.
2. Recognize current invisible markers and the exact legacy `hAiity` note.
3. Remove old owned entries from the shared `hAiity` containers and recreate active entries in their category container.
4. Preserve all unrelated events, reminders, calendars, and lists.

If a user deletes or loses one category container, the next enabled setup/foreground reconciliation creates only that missing container and restores the active entries for that category. If permissions are unavailable, the pass remains a no-op and does not clear stored state prematurely.

The old shared calendar/list is never deleted automatically. This avoids deleting a user-owned container with the same name; after marked entries are migrated, an empty legacy container can be removed manually.

## Cleanup Behavior

Keep the existing cleanup entry point and Home Screen cleanup action. Cleanup scans every accessible native container and removes only hAiity-owned current or legacy entries, including entries moved by the user or left behind by an older installation.

Cleanup reports Calendar habit entries, Calendar reminder entries, and native Apple Reminder entries separately. It does not remove native containers or unrelated content. Reconciliation remains duplicate-safe: for each hAiity UUID and destination category it retains one canonical item, removes duplicates, and recreates missing items only after successful removal.

The settings UI shows the destination category names beside the relevant sync controls so users know where entries will appear. The existing shared watermark copy action remains available for manual identification.

## Error Handling

- Missing permissions: do not create, remove, or erase stored identifiers; surface the existing permission recovery state.
- A missing stored container: resolve by identifier first, then by exact new title, then create a writable container.
- A renamed stored container: continue using it by identifier without forcing its title back.
- Failed removal or save: preserve enough state for the existing retry path and do not recreate the same item in the same pass.
- Legacy entries without a kind: treat only the exact legacy `hAiity` note as owned and remove it during migration/cleanup; do not infer ownership from arbitrary text.

## Testing

Add focused tests for:

- Routing habit and reminder Calendar plans to different destination categories.
- Stable new Calendar and Reminders container names.
- Per-category Calendar identifier persistence and legacy-key migration.
- Recreating a missing category container without affecting the other category.
- Migrating current and legacy marked entries while preserving unrelated native items.
- Separate cleanup counts for habit Calendar, reminder Calendar, and native Reminders.
- Existing duplicate, failed-removal, and reinstall-recovery paths remaining intact.

Build and runtime verification use the approved iOS 27 device only when EventKit behavior requires a device. No device hub is used.

## Acceptance Criteria

- Habit Calendar entries appear only in `hAiity Habits`.
- Reminder Calendar entries appear only in `hAiity Reminders`.
- App reminders appear only in the `hAiity Reminders` Apple Reminders list.
- Existing shared-container entries migrate without touching unrelated native content.
- Deleting one category container and running setup restores only that category.
- Cleanup can remove all hAiity-owned entries regardless of which native container currently holds them.
- No duplicate entries are created by migration, setup, foreground reconciliation, or cleanup retry.
