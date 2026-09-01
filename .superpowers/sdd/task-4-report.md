# Task 4: Integration, Migration, and Full Regression Gates

## Scope

- Baseline: `ba6bca4d9e594f02517a2f23505f8ae714f33bb8`
- Changed files: `HaiityTests/WidgetLogicTests.swift`, `HaiityTests/GitHubWidgetTests.swift`, `HaiityTests/WidgetRenderingTests.swift`
- Production changes: none. Existing `HaiityWidget.swift` and `WidgetLogic.swift` satisfied the compatibility contracts.

## Coverage Added

- Legacy Overview provider reads `WidgetData.entry()` and remains out of the widget gallery.
- Large item actions bind the current habit and do not use a parent collection URL.
- Large configuration logic contains no Habit/iCloud persistence path.
- Deleted and archived selections fall back to automatic choices.
- Locked Pro visibility is applied before configured slots.
- List, grid, and focus renderers produce non-empty output for an empty App Group snapshot.

## Verification

Focused widget gate on existing `sAiity Verification` simulator (`AC636497-5EC6-4AD4-BD83-E5E2458FA702`): **104/104 passed**.

Breakdown: GitHubWidgetTests 30/30, WidgetLogicTests 67/67, WidgetRenderingTests 7/7.

Full `HaiityTests` unit target: **1586 tests, 17 failures**. The failures are pre-existing baseline failures in AppNavigation, ThemeAndPalette, Diagnostics, Feedback, FollowUpFix, GraphContextMenuRegression, GesturePerf, ProGate, and SetupFlow. No Task 4 test failed.

`git diff --check`: passed with no output.

The requested `iPhone 16 Pro` destination does not exist in this Xcode environment; no device was created. The existing `sAiity Verification` simulator was used instead.

## Commit

Commit: `29e7769` (`test: cover large widget migration and interactions`)

## Risks

- The full unit target remains red because of the 17 unrelated baseline failures listed above.
- Simulator execution does not establish physical iPhone/iPad behavior.
- The Task 4 rendering check verifies non-empty output and stable geometry, not visual pixel approval on every device appearance.
