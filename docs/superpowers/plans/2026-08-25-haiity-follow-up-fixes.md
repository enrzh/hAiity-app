# hAiity Follow-up Fixes Implementation Plan

> Inline implementation plan for the nine requested behavior and layout fixes.

**Goal:** Keep expired Pro accounts to three visible tracked habits, make the graph and editor interactions predictable, and align appearance/search surfaces with the selected styling.

**Architecture:** Preserve all stored data and use one pure entitlement filter for app-facing active collections. Keep recurrence compatibility in `RecurrenceDraft`, but make `.once` the new-draft default and expose recurring controls only through a `Wiederholen` binding. Bound graph windows and remove direct cell gestures in the pure grid/view layer; keep Nacharbeiten exclusively in the existing long-press menu.

**Tech Stack:** SwiftUI, UIKit `UIContextMenuInteraction`, StoreKit entitlement state, XCTest, Xcode simulator.

## Tasks

1. Extend `ProGate` with `visibleActiveHabits`, then route ContentView and StatsView through that collection while preserving stored over-limit data.
2. Make the background image picker render only in `.image`, and replace palette-row checkmarks with explicit round selected/unselected controls.
3. Remove `ContributionGrid` cell selection and `HabitCard`/`ContentView` callback plumbing; add a bounded `GridCalendar.weeksForDisplay` calculation and use it for habit cards.
4. Give StatsView's context-menu host the full tile frame, hide incomplete-reminder repetition for `.once`, and redesign the recurrence section around an always-visible date plus a `Wiederholen` toggle.
5. Apply the appearance background directly to the search list.
6. Run focused and full tests, build the app, and verify changed screens and gestures in the existing iOS 27 simulator. Do not claim TestFlight upload without an observed Xcode Cloud/App Store Connect result.
