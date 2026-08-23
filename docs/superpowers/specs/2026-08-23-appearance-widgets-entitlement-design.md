# Appearance, Widgets, and Entitlement Design

## Scope

This change addresses four reported behaviors in the current hAiity app:

1. Stats and Mehr must use the same continuous native navigation-bar blur as Habits.
2. The hAiity and overview widgets must present checkbox, quantity, and yes/no habits according to their actual type.
3. Background image mode must be selectable, replaceable, removable, and switchable back to color or gradient on iOS 27.
4. Expired or revoked Pro access must restore every existing Pro gate, not only the detailed Stats gate.

The product model, stored habit schema, widget configuration intents, and developer-owner bypass remain unchanged.

## Design

### 1. Shared navigation chrome

`SettingsChromeModifier` remains the shared modifier for non-List settings surfaces, but it stops forcing a visible solid, regular-material, or ultra-thin navigation-bar background. It only supplies the themed page background. The system navigation container is then allowed to draw its native material continuously over the page, matching the Habits navigation stack on iOS 27.

Settings rows and cards continue to use the existing Solid, Milchglas, Liquid Glass, and Auto surface modifiers. This change is limited to navigation-bar ownership and does not remove the appearance choices from settings pages.

### 2. Native background controls

The background mode control uses a native segmented `Picker` for `Farbe`, `Verlauf`, and `Bild`. The selected mode remains the single source of truth in `AppearancePreferences`.

Image selection uses a direct `PhotosPicker` control instead of attaching a presentation modifier to a separate `Button`. Image removal remains a separate destructive button. Leaving image mode clears the stored image data; selecting image mode without data shows the native picker, so the user is never trapped in an empty image state.

All mutations continue through `HabitStore.appearancePreferences`, which synchronously writes the app-group payload and marks the appearance timestamp. Existing iCloud merge rules remain in place. Tests cover mode transitions, removal, JSON round-tripping, and newer remote appearance replacement.

### 3. Type-aware widgets

`WidgetLogic` gains one shared, pure display summary for a single item. Both widget views consume this summary instead of independently deciding what the status glyph and text mean.

- Checkbox habits keep the checkmark/open status and streak presentation.
- Quantity habits show current value versus target and a progress-oriented status.
- Yes/no habits show `Ja`, `Nein`, or `Offen` with matching positive, negative, or neutral symbols.
- Tracked habits of all three kinds retain their graph.
- Reminder items remain excluded from the overview roster and graph-only widget paths, as required by the current product behavior.

The shared model is unit-tested for all three habit kinds, including empty, partial, complete, and declined states. Rendering tests continue to render light, dark, and vibrant widget variants.

### 4. Live Pro entitlement and gates

`Pro.isUnlocked` remains the only read point used by views. On app launch and when the scene becomes active, the app performs a current-entitlement check that accepts only a verified, non-revoked, directly purchased transaction for the product. If StoreKit reports no current entitlement, the cached Pro state is downgraded. The transaction listener continues to handle purchases, cross-device changes, and revocations immediately.

The automatic check does not invoke `AppStore.sync()` and therefore does not unexpectedly prompt for an Apple ID password. The explicit Restore button remains the path for a complete account-history refresh.

Existing Pro entry points remain guarded by the same live entitlement:

- creating a fourth tracked habit;
- creating a new custom palette;
- applying a custom icon color;
- enabling either Calendar mirror;
- enabling native hAiity Reminders sync;
- reading detailed per-habit Stats.

Disabling an integration and exporting/importing data remain available after expiry so the user cannot be trapped or lose access to their data. Tests add a regression contract that each feature reads the shared entitlement and that a no-entitlement refresh can downgrade the cache.

## Failure handling

- A failed image import leaves the previous valid image and mode unchanged and displays the existing error hint.
- Removing an image cancels any pending import result so an older asynchronous picker task cannot restore it.
- A failed or unavailable StoreKit check preserves the last known state unless StoreKit has completed a valid current-entitlement result; an explicit Restore failure remains visible on the paywall.
- No iCloud merge is allowed to make a locally selected appearance look successful unless the resulting payload actually contains the selected mode.

## Verification

The implementation is complete only after:

1. focused red-green tests for appearance transitions, widget summaries, and entitlement downgrade;
2. the full `HaiityTests` suite;
3. simulator runtime screenshots of Stats, Mehr, and Darstellung in at least image and glass modes;
4. runtime interaction checks for switching background modes, selecting an image, removing it, and changing it;
5. `git diff --check` and a release build verification.

No TestFlight upload is part of this change unless explicitly requested after verification.
