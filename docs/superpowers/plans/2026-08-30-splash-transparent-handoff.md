# Splash Transparent Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reveal the mounted app during a faster splash fade without a white or black compositor frame.

**Architecture:** Keep the existing SwiftUI root and UIKit/Core Animation splash. Correct the overlay's transparency contract and shorten only the existing timeline constants; add no new state manager or readiness service.

**Tech Stack:** SwiftUI, UIKit, Core Animation, XCTest, iOS 17+

## Global Constraints

- Modify only `Haiity/Views/StartupSplashView.swift`, `Haiity/Models/StartupSplash.swift`, and `HaiityTests/StartupSplashTests.swift`.
- Preserve the center-to-three-graphs-to-zoom sequence and Reduce Motion path.
- Keep `ContentView` mounted beneath the overlay and retain `CATransaction.setCompletionBlock` plus the `didFinish` guard.
- Do not change iCloud, App Group, App Intent, deep-link, subscription, Calendar, Reminder, or widget behavior.
- Use simulator `AC636497-5EC6-4AD4-BD83-E5E2458FA702`; do not start another simulator.

---

### Task 1: Faster Transparent Splash Handoff

**Files:**
- Modify: `Haiity/Views/StartupSplashView.swift`
- Modify: `Haiity/Models/StartupSplash.swift`
- Test: `HaiityTests/StartupSplashTests.swift`

**Interfaces:**
- Consumes: `StartupSplashTimeline`, `StartupSplashAnimationView`, and the existing mounted `ContentView` root.
- Produces: one transparency-capable splash overlay whose animated `backgroundLayer` reveals the app beneath.

- [ ] **Step 1: Write failing contracts.** Add tests asserting that `StartupSplashView` has no `.background(Color(.systemGroupedBackground))`, `StartupSplashAnimationView` uses `isOpaque = false`, the root remains mounted, total normal duration is at most 1.35 seconds, start delay is at most 0.02 seconds, and overlay opacity remains positive before completion.

- [ ] **Step 2: Verify RED.** Run the focused `StartupSplashTests` on simulator `AC636497-5EC6-4AD4-BD83-E5E2458FA702` with a 240-second hard timeout. The new transparency and timing assertions must fail on the old code.

- [ ] **Step 3: Implement the minimum fix.** Remove the opaque SwiftUI splash background, set the UIKit view to non-opaque, and set `clusterDuration = 0.18`, `splitDuration = 0.58`, `zoomDuration = 0.54`, and `startDelay = 0.02`. Keep all existing animation structure and completion behavior.

- [ ] **Step 4: Verify GREEN.** Re-run `StartupSplashTests` with the same bounded command and require a nonzero XCTest count with zero failures. Run `git diff --check`.

- [ ] **Step 5: Commit.** Stage only the three allowed files and commit with `speed up transparent splash handoff`.
