# Settings Chrome and Image Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make appearance controls, settings chrome, and setup surfaces coherent with the selected background/material, then verify and release the app to TestFlight.

**Architecture:** Reuse `AppearancePreferences`, `AppearanceBackground`, `AppSurfaceModifier`, and `SettingsChromeModifier`. Update the image control and dynamic-icon row in `MoreView`; use the shared navigation modifier for Stats, Mehr, and `ReminderSetupView`. Keep the existing `HabitStore` persistence change from the previous fix.

**Tech Stack:** SwiftUI, PhotosUI, UIKit materials, XCTest, Xcode Cloud/TestFlight.

## Global Constraints

- Preserve the existing uncommitted background responsiveness fix.
- Preserve unrelated `.superpowers/` and `build/` artifacts.
- Use `String(localized:)` for new visible text.
- Do not add a second appearance or persistence system.
- Verify UI with simulator screenshots before release claims.

### Task 1: Add regression contracts

**Files:**
- Modify: `HaiityTests/ThemeAndPaletteTests.swift`
- Modify: `HaiityTests/FeedbackTests.swift` only if the existing MoreView source contract belongs there.

- [ ] Add tests that require the MoreView dynamic-icon label to contain a horizontal icon/title stack, the image action to expose `appearance-background-picker`, `appearance-background-remove`, and a styled action surface, and the settings chrome to keep a visible material navigation background for Liquid Glass.
- [ ] Run the focused tests and confirm they fail against the current source.

### Task 2: Update shared settings chrome

**Files:**
- Modify: `Haiity/Theme.swift`

- [ ] Change the Liquid Glass branch of `SettingsChromeModifier` from a hidden navigation background to visible `.ultraThinMaterial`; keep the iOS fallback material path.
- [ ] Use the same visible material treatment for Auto so the navigation bar does not become an opaque dark block over image backgrounds.
- [ ] Run the focused source/material tests and confirm they pass.

### Task 3: Polish appearance controls

**Files:**
- Modify: `Haiity/Views/MoreView.swift`

- [ ] Replace the current borderless image selection label with a material action tile using `photo.on.rectangle.angled`, localized `Bild auswählen`, and the existing PhotosPicker binding/identifier.
- [ ] Keep removal recoverable and compact with a destructive trash action, localized accessibility text, and the existing `appearance-background-remove` identifier.
- [ ] Replace the Toggle label VStack with an `HStack` containing the icon and title/subtitle VStack so `App-Icon dynamisch` stays on one line with its icon.
- [ ] Keep all existing state bindings, persistence, and PhotosPicker loading behavior unchanged.
- [ ] Run the focused tests and rebuild the simulator app.

### Task 4: Runtime visual verification

**Files:**
- No production files unless a screenshot exposes a real regression.

- [ ] Install and launch the Debug app on simulator `084680DC-DFE9-47D4-9E62-FF4D597374F0`.
- [ ] Capture Darstellung with color, gradient, and image modes; select and remove a test image.
- [ ] Capture Stats, Mehr, and setup in light/dark plus Solid, Milchglas, Liquid Glass, and Auto; confirm the header uses background-aware blur and all rows/cards follow the selected material.
- [ ] Run `git diff --check` and the full XCTest suite; record test counts and any warnings.

### Task 5: Release and TestFlight

**Files:**
- Modify only release version/build metadata if the repository release script requires it.

- [ ] Run `tools/release.sh` in its supported non-upload validation mode and confirm the release build succeeds.
- [ ] Commit only the relevant production, test, spec, and plan files; exclude `.superpowers/` and `build/` artifacts.
- [ ] Push the branch required by the repository’s Xcode Cloud workflow.
- [ ] Trigger the hAiity Xcode Cloud archive/upload workflow, verify the build is processed in App Store Connect, and report the build number and processing state without claiming TestFlight availability before direct confirmation.
