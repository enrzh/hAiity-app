# Settings Chrome and Image Controls Design

## Goal

Make the appearance controls and background-aware settings pages feel like one
coherent hAiity surface on iOS 27, while preserving the existing persisted
appearance model and adaptive material behavior.

## Design

`Theme.swift` remains the single source of truth for app surfaces and settings
chrome. Settings navigation bars use visible native material instead of a
hidden bar in Liquid Glass mode, matching the blurred Habit-page chrome and
allowing the selected background to continue through the header. Solid keeps
its opaque grouped background; Milchglas, Liquid Glass, and Auto keep their
existing row treatment.

`MoreView` keeps the current PhotosUI flow and persistence but presents image
selection as a material action tile with a clear photo affordance and a compact
destructive remove control. The dynamic app-icon toggle uses one horizontal
icon/title/subtitle row, with the switch aligned at the trailing edge.

More and setup continue to use `settingsSurface`, `settingsChrome`, and
`appSurface`; only hard-to-read or opaque local styling is adjusted. No second
appearance abstraction, background storage, or per-page material switch is
introduced.

## Verification

- Add source-contract tests for the inline dynamic-icon row, styled image
  action identifiers, and visible material navigation chrome.
- Run the focused appearance tests and the full XCTest suite.
- Build and install the Debug app on the iOS 27 simulator.
- Inspect Darstellung with color, gradient, and image backgrounds, then inspect
  Stats, Mehr, and setup with Solid, Milchglas, Liquid Glass, and Auto in light
  and dark appearance. Confirm no header remains an opaque dark block and no
  control text overlaps.
- Create a signed release build and upload it through the supported Xcode Cloud
  TestFlight workflow after verification.
