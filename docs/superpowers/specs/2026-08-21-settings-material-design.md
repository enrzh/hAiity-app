# Settings Material Consistency Design

## Goal

When `Milchglas` or `Liquid Glass` is selected in `Darstellung`, every More/settings page uses the same material treatment as the habit and statistics surfaces. `Solid` remains the existing opaque treatment.

## Design

Keep `AppearancePreferences`, `AppearanceBackground`, `AppSurfaceModifier`, and `SettingsSurfaceModifier` as the single material source of truth. Apply the existing settings surface at the More route destination boundary so nested pages cannot accidentally omit the selected background, row surfaces, or navigation-bar treatment. Do not add a second material abstraction or duplicate per-page styling.

The route wrapper covers the main More list, the dedicated Darstellung and Verhalten & Teilen lists, and route pages such as Archiv, Über, Entwickler, and GitHub. Existing pages that already call `.settingsSurface()` remain unchanged; the wrapper is idempotent for those pages and provides the missing chrome for routes that do not.

## Verification

- Add a source-contract test proving the More route destination applies `.settingsSurface()` after constructing the route view.
- Run the focused appearance tests and the full release test command.
- Build the app for the iOS simulator and inspect the More/settings page with Liquid Glass selected in both light and dark appearance. Confirm rows, page background, and navigation bar use the same visual treatment without overlap or unreadable text.
