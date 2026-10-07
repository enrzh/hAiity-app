# Product simplification implementation

## Scope

Implement the ten accepted product improvements using existing SwiftUI components,
recurrence engines, persistence, purchase boundaries, and graph renderer. This is
local implementation and verification, not a release request. Version/build remain
1.0.0 (276). Preserve the pre-existing notification-banner fix and device report.

## Acceptance criteria

1. A new habit starts daily and a new reminder starts once. Changing repetition
   never silently changes the item type; editing preserves saved type/schedule.
2. Creation puts name, repetition, essential reminder date/time, preview, and Save
   first. Optional kind and settings remain discoverable and retain saved values.
3. Every habit card offers a separate, accessible Today action. Recent progress is
   readable without stretching a short history into oversized cells.
4. History and Edit are explicit targets; long-press remains an optional shortcut.
5. Only genuinely fresh data gets Quiet. Existing/legacy appearance, customized
   materials, backgrounds, palettes, and accessibility fallbacks remain unchanged.
   Alternative design styles move into Customize.
6. Sentence creation is optional inside the creator. Remove its floating global
   action, retain dictation/parser/fallback, and show useful readiness/setup rather
   than model engineering in normal settings. Preserve saved model choices.
7. Personalization centers on a nickname. GitHub hub entry navigates to its page;
   connection actions stay there. Optional Apple identity remains reachable without
   dominating the hub; identity and StoreKit access are never silently cleared.
8. Statistics prioritize truthful recent and weekly completion. Existing per-habit
   information, history routes, customized cards, and Pro gates remain available;
   AI reading and zero streaks do not dominate the page. Do not change metric math.
9. Expose the existing flexible weekly recurrence as N times per week, any day.
   Reuse current recurrence and completion engines, including saved-data handling.
10. Today check-off, undo, graph, and progress stay consistent immediately. Reuse
    existing widget invalidation and efficient snapshots; physical responsiveness
    and Home Screen behavior require separate device evidence.

## Ownership

- Creator worker: EditHabitSheet and isolated creator product tests.
- Habit-card worker: HabitCard and isolated card product/UI tests; renderer changes
  only after an additive API agreement.
- Statistics worker: StatsView, StatsCardPrefs segment if needed, isolated tests.
- Main: navigation/settings/default integration, shared test contracts, all locale
  changes, project generation, integration review, native builds/tests and report.

All workers use sub2api/gpt-6.1-sol and do not run Xcode builds. Reuse shared
AppSettingsRow/AppSettingsGroup/AppIconBadge and ContributionTiles; no new component
framework, persistence rewrite, paywall presenter, or dependency.

## Verification

- Baseline: native Unit, serial iOS simulator, 2,113 passed / 0 failed, before edits.
  Evidence: /Users/enricomini/Documents/haiity-verification/product-simplification-20261007/Baseline.xcresult.
- Review implementation and saved-data boundaries; update obsolete source contracts
  alongside behavior tests rather than concealing missing files or weakening gates.
- Regenerate the explicit Xcode project using tools/generate-project.sh.
- Run focused native checks, full Unit, and relevant native UI checks covering
  creator defaults/editing/flexible weeks, presentation handoff/deep links, card
  check-off/undo/history/edit, Statistics, Personalization, fresh-install/default
  preservation, Customize, narrow/AX/RTL and light/dark layouts.
- Run a generic Release build; bind final results to the actual source fingerprint.
- Review generated screenshots. Simulator results are not physical-device proof.

## Separate pending device gates

The prepared notification-only binary was not installed: CoreDevice 4016 and an
unavailable iPhone Air blocked transfer. Keep that evidence intact. Combined product
changes need a new binary for any later device session. Notification panel behavior,
real-data startup stall, Cloud/native services, Home Screen widgets, and finger/VO
interaction remain pending until the phone is available. No upload, commit, push,
new build number, recording, or data-corpus access is implied by this plan.
