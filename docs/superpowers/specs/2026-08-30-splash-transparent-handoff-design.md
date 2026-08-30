# Splash Transparent Handoff Design

## Goal

Make startup faster and reveal the already-mounted app continuously while the splash tiles zoom and fade, without a white or black intermediate frame.

## Root Cause

`StartupSplashAnimationView` fades its Core Animation `backgroundLayer`, but `StartupSplashView` also installs an opaque SwiftUI grouped background. The UIKit view is marked opaque even though its layers become transparent. That combination prevents the app beneath from appearing during the fade and gives the compositor an invalid opaque/transparent contract.

## Design

- Keep `ContentView` mounted beneath the splash from the first scene frame.
- Let `backgroundLayer` be the splash's only full-window background.
- Remove the SwiftUI splash background and mark the UIKit animation view non-opaque.
- Preserve the center-to-three-graphs-to-zoom sequence, but shorten the delay and three phases to roughly 1.3 seconds total.
- Keep the background and tile opacity animations alive until the Core Animation completion removes the overlay.
- Preserve Reduce Motion, cancellation, cached rasterization, iOS 17 compatibility, and the one-shot completion guard.

## Verification

- A focused contract must fail on the old opaque wrapper and `isOpaque = true` behavior.
- Timeline tests must assert the shorter duration while retaining a nonzero overlay opacity before completion.
- `StartupSplashTests` must execute with a nonzero passing count.
- The generic iOS `build-for-testing` gate must succeed without signing.

