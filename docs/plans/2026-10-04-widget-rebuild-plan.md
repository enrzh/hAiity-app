# Widget rebuild

Date: 2026-10-04
Scope: rebuild presentation of existing widgets and Live Activities, without new
widget kinds, configuration choices, dependencies or data/sync systems.
Base: main, `109a06d9bfc0633e59b8d45abc60cd25aad4a0dc`, 1.0.0 (273).

## Design

- One native widget canvas. Clear item identity, readable current state and
  independent actions; avoid repeated completion badges and nested card borders.
- Small/medium: one item, a useful graph for tracked habits, a clear status for
  reminders, and explicit native intent buttons. Reset has a separate header
  target when the small footer would become crowded.
- Large main widget: two graph-led selected items. List: four equal rows. Grid:
  four two-column tiles with sparse fallback. Focus: one dominant item and a
  concise queue. Preserve configured item order.
- Pure habit/GitHub widgets keep seven chronological rows, square tiles and
  shared ContributionTiles. Center the band and preserve all five intensity
  levels rather than mapping several positive levels to the same fill.
- Lock-screen layouts remain monochrome-safe. Reminders show their status rather
  than invented streaks/history. Live Activities retain system-rendered timers,
  progress and existing intents while improving hierarchy and action targets.
- Inherit the saved app design style through the existing timeline snapshot.
  Adapt typography and grouping to fixed widget families; let WidgetKit own
  native tinted/clear appearance and content margins.

## Implementation and protection

Reuse Theme, WidgetLogic, GraphLayout, ContributionTiles and existing AppIntents.
Extract only repeated identity/status/actions/progress into WidgetComponents.
Keep configuration kinds/entities, Pro visibility, explicit selection, per-item
time zones, positive/negative/free-day semantics, reset preference and coordinated
writes. No widget renderer reads a live store or performs network work.

Replace stacked fixed-height assumptions with composition budgets derived from
available space. Every independent Home Screen action has a 44 pt hit region.
Names can use two lines; accessibility labels retain full names/values. Support
RTL text while keeping chart chronology left-to-right.

## Verification

Baseline: 152 widget logic/rendering/GitHub tests passed, zero failed/skipped.
Artifacts: `/Users/enricomini/Documents/haiity-verification/widgets-rebuild-20261004`.
Prior dirty/untracked changes preserved, baseline patch/status/fingerprint saved.

Verify all existing item kinds, zero/sparse/dense entries, reset on/off, long
names, custom palettes, light/dark/full-color/accented/vibrant rendering, RTL and
accessibility text. Render the actual production views at multiple family sizes;
check distinct data fills, bounded regions and independent action targets. Update
obsolete literal-layout tests without weakening data/action/configuration tests.

Finish with a complete native Unit suite, appropriate app Smoke regression,
unsigned generic iOS Release build and source-bound evidence/report. Native
widget-host tint/touch, Control Center and real Live Activity delivery remain
physical-device verification gates. This task does not authorize a release,
upload, signing change, commit, push or physical-device installation.
