# Motivation Feed And Notification Modes

## Goal

Add a larger pool of daily motivational messages while keeping hAiity reliable
offline, and replace the per-item notification boolean with a three-state
notification choice. The open-source content feature is opt-in and must not
make notification delivery depend on a network request.

## Approved product behavior

### Optional open-source messages

- The setting is off by default and is presented as an optional enhancement,
  not as a required setup step.
- The existing bundled, localized motivation pool remains available forever as
  the fallback.
- When enabled, hAiity downloads a small JSON feed from one source with a
  clearly verified open-source/public-domain license. The feed URL, source
  name, license, attribution URL, and schema version are fixed in the app.
- The request contains no account, habit, device, or personal data. It uses
  HTTPS, a bounded timeout, and a bounded response size.
- Valid messages are cached locally in the App Group. The user preference is
  part of the normal `HabitData`/iCloud settings; downloaded content is not
  synced through iCloud.
- Refresh occurs only after opt-in and when the cache is stale. A failed
  request is silent and leaves the previous cache intact. If no cache exists,
  the built-in pool is used.
- Remote entries are schema-checked, language-filtered, length-limited, and
  discarded when malformed. Unsupported device languages use the existing
  local messages.
- Local date-based selection remains deterministic. The same day and cache
  version produce the same message, so rescheduling does not pick randomly.
- The UI shows concise attribution and a source/license link. Disabling the
  setting deletes the remote cache and reschedules from the bundled pool.

### Per-habit and per-reminder notification choice

Replace the standalone `Benachrichtigung` toggle with a mutually exclusive
three-state selector shown when the item has a scheduled time:

1. `Aus`: no scheduled notification for this item.
2. `Standard`: the existing local notification behavior.
3. `Zeitkritisch`: a local notification with iOS's
   `UNNotificationInterruptionLevel.timeSensitive`.

The UI should use short localized labels and a native one-of-three control.
The app's own Do Not Disturb setting still suppresses hAiity scheduling; the
time-sensitive mode must not silently bypass an explicit hAiity DND choice.
The product UI should call this mode `Zeitkritisch`/`Time Sensitive`, not
`Critical Alert` or `Emergency`, because Critical Alerts require a separate
Apple entitlement and can bypass system mute/focus controls.

Existing timer behavior stays separate:

- Starting a habit session continues to use the existing Live Activity path.
- Finishing a timed session continues to record start/end time and duration.
- Any existing session milestone or end notification remains governed by the
  current timer/session implementation, not by the scheduled-item selector.
- A local notification cannot start a non-push Live Activity while the app is
  terminated, so the implementation must not promise that behavior.

## Data model and migration

Add an additive, Codable notification-mode value to `Habit`. Preserve
`notificationsEnabled` for one compatibility cycle so older builds can still
read the file:

- Decode the new mode when present.
- Otherwise map `true` to `.standard` and `false` to `.off`.
- Encode the new mode and keep the legacy boolean as `true` for `.standard` or
  `.timeSensitive`, `false` for `.off`.
- New habits default to `.standard`, matching the current default behavior.
- iCloud merge copies the new mode along with the existing per-item fields.
- Scheduling uses the new mode as the source of truth and never schedules an
  item in `.off` mode.

Add an additive `openSourceMotivationEnabled` preference to the existing
persisted preference model, defaulting to `false`, and include it in the
existing iCloud merge path. Keep the cache outside `HabitData` so remote
content does not inflate or overwrite the user record.

## Data flow

1. More settings changes the opt-in preference.
2. Enabling starts a bounded fetch; disabling clears the local cache.
3. The cache loader returns valid localized remote entries, or an empty result.
4. `Motivation` combines the remote body pool with the existing local opener
   and fallback logic.
5. `Reminders.reschedule` creates the next seven daily motivation requests
   from that resolved pool, preserving the existing notification budget.
6. Habit/reminder scheduling maps `.standard` to the current content and
   `.timeSensitive` to the same content with the interruption level set.

No new server, account, background daemon, or notification provider is needed.
A small cache/data helper may be added next to the existing motivation model;
avoid introducing a manager/factory/protocol layer for one feed.

## Failure and safety rules

- No network request is made while the feature is disabled.
- No personal data is sent to the source.
- HTTP errors, invalid JSON, oversized payloads, unsupported languages, and
  timeouts all fall back without blocking the UI.
- The last valid cache is retained through transient failures.
- Remote text is never allowed to replace the bundled pool entirely.
- If the feed license or attribution cannot be verified, the source is not
  shipped.
- Time-sensitive notifications remain subject to the user's system settings
  and hAiity's explicit DND state.

## Testing

Add focused tests for:

- default-off preference and persistence/iCloud round trip;
- valid feed decoding, filtering, cache expiry, cache clearing, and fallback;
- unsupported language fallback and deterministic daily selection;
- no network path when disabled;
- old `notificationsEnabled` JSON migration and new three-state round trip;
- one scheduled request for standard/time-sensitive modes and none for off;
- correct interruption level for time-sensitive requests;
- DND suppression and preservation of timer/session behavior;
- existing motivation pool, notification budget, and ActivityKit tests.

## Non-goals

- No live multi-source aggregation.
- No quote scraping from sites with unclear rights.
- No critical-alert entitlement.
- No attempt to start Live Activities from a terminated app using a local
  notification.
- No change to the existing bundled localized messages beyond adding more
  entries.
