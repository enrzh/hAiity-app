# Selbstanpassende Darstellung Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted `Selbstanpassend` surface mode that derives readable UI tint and GitHub tile contrast from the selected background.

**Architecture:** Extend `AppearanceMaterial` and keep `AppearancePreferences` as the only stored appearance source. Add pure, testable adaptive color calculations in `Theme.swift`; apply them in the shared surface/background modifiers and in `GitHubContributionGraph` through the existing environment. Preserve the selected graph palette and make older payloads fall back to solid when they do not know the new compatibility marker.

**Tech Stack:** SwiftUI, UIKit color/image sampling, Codable, XCTest, XcodeGen-generated iOS target.

## Global Constraints

- Preserve the existing `hAiity` app name and unrelated untracked worktree files.
- Keep the selected graph palette; adaptive mode may only shift colors for contrast.
- New visible UI text uses `String(localized:)` and `Localizable.xcstrings`.
- Do not add a second persistence store or change widget configuration behavior.
- Verify UI changes with simulator screenshots before claiming completion.

---

### Task 1: Add the adaptive appearance model and color resolver

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- `AppearanceMaterial.adaptive` and display name `Selbstanpassend`.
- `AppearancePreferences` encodes adaptive mode as `material: solid` plus `adaptive: true` and decodes both that form and ordinary legacy material values.
- `Theme.adaptiveReferenceHex(preferences:dark:) -> UInt32`.
- `Theme.adaptiveTintHex(preferences:dark:) -> UInt32`.
- `Theme.adaptivePalette(_:preferences:dark:) -> PaletteStyle`.

- [ ] **Step 1: Add failing tests** for adaptive enum display, Codable round-trip, legacy fallback, color/gradient reference resolution, and minimum tile contrast against the reference background.
- [ ] **Step 2: Run the focused tests** with `xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -only-testing:HaiityTests/AppearanceSettingTests -only-testing:HaiityTests/ThemeAndPaletteTests`; expect failures for the missing case and functions.
- [ ] **Step 3: Implement the minimal model and resolver** in `Theme.swift`, including UIKit image average sampling with a system-background fallback and palette channel adjustment toward black or white only when contrast is insufficient.
- [ ] **Step 4: Run the focused tests again** and require them to pass.
- [ ] **Step 5: Commit** with `git add Haiity/Theme.swift HaiityTests/ThemeAndPaletteTests.swift && git commit -m "Add adaptive appearance color resolver"`.

### Task 2: Apply adaptive surfaces and GitHub tile contrast

**Files:**
- Modify: `Haiity/Theme.swift`
- Modify: `Haiity/Views/GitHubContributionGraph.swift`
- Modify: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- `AppSurfaceModifier` handles `.adaptive` with a background-derived tint and the existing iOS 26 glass / older material fallback.
- `AppearanceBackground` adjusts image scrim strength only for `.adaptive`.
- `GitHubContributionGraph` resolves its palette from `appearancePreferences` and adds a subtle outline only in adaptive mode.

- [ ] **Step 1: Add source-contract tests** asserting the adaptive surface branch, environment read, and adaptive tile outline.
- [ ] **Step 2: Run the focused source tests** and observe the missing implementation failure.
- [ ] **Step 3: Implement shared adaptive surface rendering** without changing solid, milky, or liquid behavior.
- [ ] **Step 4: Implement adaptive palette/outline rendering** in `GitHubContributionGraph` while preserving its existing layout and palette input.
- [ ] **Step 5: Run appearance and GitHub graph tests** and require them to pass.
- [ ] **Step 6: Commit** with `git add Haiity/Theme.swift Haiity/Views/GitHubContributionGraph.swift HaiityTests/ThemeAndPaletteTests.swift && git commit -m "Apply adaptive surfaces to GitHub graph"`.

### Task 3: Expose and localize the option

**Files:**
- Modify: `Haiity/Views/MoreView.swift` only if the picker needs an explicit accessibility label.
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `HaiityTests/ThemeAndPaletteTests.swift`

**Interfaces:**
- Existing `ForEach(AppearanceMaterial.allCases)` exposes the new case without a second picker.
- Localization key `Selbstanpassend` has German source text and English plus existing supported-language translations.

- [ ] **Step 1: Add a source-contract test** that the Darstellung picker derives its options from `AppearanceMaterial.allCases` and contains the adaptive label.
- [ ] **Step 2: Add the localization entry** and validate the strings file as JSON.
- [ ] **Step 3: Run the focused tests** and require them to pass.
- [ ] **Step 4: Commit** with `git add Haiity/Localizable.xcstrings Haiity/Views/MoreView.swift HaiityTests/ThemeAndPaletteTests.swift && git commit -m "Expose self-adjusting appearance option"`.

### Task 4: Runtime verification

**Files:**
- No source changes unless a focused regression is found.

- [ ] **Step 1: Run `git diff --check`, the focused appearance/GitHub tests, and the full repository release test gate without uploading.**
- [ ] **Step 2: Generate/build the app and launch the simulator.**
- [ ] **Step 3: Inspect `Mehr > Darstellung` with color, gradient, and image backgrounds in light and dark appearance; verify all four surface choices still render distinctly.
- [ ] **Step 4: Inspect the GitHub contribution card in each background mode and verify tile boundaries, l0, and l4 remain visible without text overlap.
- [ ] **Step 5: Report screenshots and any unverified device-only behavior; do not claim TestFlight release unless separately requested.
