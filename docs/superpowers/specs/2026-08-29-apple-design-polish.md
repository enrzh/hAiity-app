# Apple Design Polish for hAiity

## Goal

Smooth the existing hAiity experience so navigation, settings, launch, habit
cards, statistics, and widgets feel like one native Apple product. Preserve
current behavior, iCloud data, App Intents, deep links, and iOS 17+ support.

## Design Decisions

### 1. Shared appearance system

Use the existing appearance state and rendering primitives in `Theme.swift` as
the source of truth. Solid, Milchglas, Liquid Glass, and adaptive modes should
share the same spacing, shape, semantic foreground colors, and readability
rules. Background images and gradients remain user data, but their rendering
must not block interaction or force duplicate decoding. When the system asks
for reduced transparency, prefer an opaque readable surface while retaining
the selected color treatment.

Do not add a new theme manager, provider, or design framework. Extend existing
view modifiers only when a shared rule cannot be expressed in the current
`Theme` helpers.

### 2. Navigation and chrome

Keep the native iOS tab bar as the primary navigation on supported OS versions.
The older fallback remains available for older systems, but both paths should
use the same visual spacing, safe-area handling, and action hierarchy. Search
and create remain actions, not additional content tabs. Search opening and
closing should preserve the existing transition without leaving an overlay,
shadow, or blank frame behind.

### 3. Settings and setup

Apply the same settings surface and row treatment to Mehr, Verhalten & Teilen,
Darstellung, and setup. Prefer short labels, one clear control per row, native
pickers, and consistent section spacing. Settings pages should inherit the
selected appearance without making text or controls lose contrast. Setup should
use the full available screen, keep the primary action reachable, and present
permission requests at the point where their purpose is clear.

### 4. Launch handoff

Keep the splash animation lightweight and let the real app prepare underneath
it. Use the existing launch image/cache path and a single final opacity/scale
handoff so there is no blank gap or abrupt replacement. Respect Reduce Motion
with a short non-animated handoff. The splash must not perform synchronous
image decoding or delay the first usable app frame.

### 5. Cards, enlarged views, and widgets

Use one surface contract for habit cards, statistics cards, enlarged previews,
and widgets: the visible rounded shape owns its clipping, border, and shadow;
source views must not leave a second shadow behind during enlargement. Content
must stay inside stable geometry, with graph-first hierarchy, one-line title
truncation, Dynamic Type support, and at least 44pt interactive targets.

Large widgets should remain glanceable: show only the information needed for a
quick decision, keep graph area dominant, and avoid text or emoji being clipped.
Reminder cards stay graph-free. Existing App Intent actions, links, and widget
configuration choices remain unchanged.

## Data and Compatibility

- No changes to the habit, reminder, iCloud, or App Group payload formats.
- No changes to entitlement, subscription, native Calendar, or native Reminder
  behavior.
- No new external dependency.
- Preserve the iOS 17+ target and conditional native iOS 26+ navigation path.
- Preserve existing user-selected background images and palettes.

## Implementation Order

1. Harden shared appearance and settings surfaces.
2. Align navigation/search chrome and setup presentation.
3. Reduce splash handoff work and connect its completion to the prepared app
   surface.
4. Normalize card/enlarged-preview surfaces and large-widget geometry.
5. Run focused tests, the full available test suite, `git diff --check`, and a
   generic iOS build-for-testing.

## Acceptance Criteria

- Every settings page uses the selected material and remains readable in light,
  dark, image, gradient, and reduced-transparency cases.
- The app shows no duplicate bottom navigation chrome and no search-closing
  artifact or blank handoff frame.
- The first app content is visible beneath the splash handoff; image
  backgrounds do not add a synchronous launch delay.
- Enlarged cards and graphs have exactly one shadow/border around the visible
  rounded surface and no clipping at the bottom or sides.
- Large widgets keep titles, emojis, graphs, and action controls within their
  bounds at supported families and Dynamic Type sizes.
- Existing behavior and regression tests remain green.
