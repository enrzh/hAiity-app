# hAiity UI Task1 Review Fix Report

## Scope

Base: `05eb929`, follow-up corrections on `b456209` and `3cc0896`. Closed the remaining Task1 layout and rendering-test evidence gaps without changing unrelated work.

## Changes

- Liste uses one `titleStatusBand` HStack at `18pt`, then `4pt` spacing and a `38pt` graph, totaling `60pt` per non-reminder item; the list has four natural child gaps: `20 + 4x72 + 4x4 = 324pt`, with no bottom spacer child.
- Every action in the compact and large paths owns its own `44 x 44pt` frame. Actions remain outside the informational `Link`.
- Large item status metadata and reminder marks use small done/declined/open/free tints; no full-row status fill is added.
- Fokus calls the shared item with `preserveFocusSurface: true`, restoring the prior `padding(4)` plus rounded 8pt accent background/clip while Liste remains unframed.
- Raster uses `gridColumnGap` for its actual 8pt column spacing and `gridRowGap` for its 6pt row spacing.
- Rendering tests now slice the actual LargeWidgetItem/Liste regions, cover per-action hit-target contracts, reset visibility, status branches, and render at both `accessibilityLarge` and `accessibilityExtraExtraExtraLarge` with 664x712 output and visible-content assertions.
- Liste accessibility tests now inspect scale-2 row bounds for all four 72pt rows: each non-reminder title/status region and graph region has foreground pixels, inter-row gaps remain quiet, content ends at the 332pt bottom, and reminder rows require bell/status foreground without a graph assertion. Reset enabled and disabled states each render independently.

## Verification

- Existing booted simulator: `sAiity Verification` (`AC636497-5EC6-4AD4-BD83-E5E2458FA702`)
- `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=AC636497-5EC6-4AD4-BD83-E5E2458FA702' -only-testing:HaiityTests/WidgetRenderingTests`
- Result: `WidgetRenderingTests` 17/17 passed; `** TEST SUCCEEDED **`.
- `git diff --check` passed before the final test run.
- Full `WidgetRenderingTests`: 17/17 passed with `xcodebuild test` on the existing simulator.

## Commit

Test-evidence commit: `2e27bb8`; this wording correction is a report-only follow-up. No push performed.
