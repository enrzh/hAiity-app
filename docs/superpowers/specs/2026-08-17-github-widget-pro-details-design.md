# GitHub Graph Widget and Pro Details Design

## Goal

Allow the existing Graph widget to display either a selected habit graph or the connected GitHub contribution graph, add a preference for hiding the GitHub username above the in-app graph, and keep the hAiity Pro row useful after the entitlement is active.

## Scope

- GitHub selection is available only in the existing Graph widget.
- The main habit widget and lock-screen streak widget keep their current habit-only configuration.
- The GitHub username preference applies to the username heading on the in-app GitHub contribution card.
- The Graph widget remains graph-only and does not add a username heading.
- The active Pro row opens the existing Pro feature sheet without offering a second purchase.

## Architecture

### Graph widget selection

Introduce a dedicated `SelectGraphIntent` and `GraphWidgetSource` AppEnum. The intent has a source parameter with `Habit` and `GitHub` cases and keeps the optional habit parameter for the habit case. Only `HaiityGraphWidget` adopts this intent, so unrelated widgets never expose GitHub as a configuration choice.

The widget entry gains the selected graph source and an optional GitHub snapshot. A graph-specific provider resolves the selected habit or reads the GitHub snapshot from shared storage. Existing habit providers and entry behavior remain unchanged.

### Shared GitHub snapshot

Move the persisted GitHub contribution snapshot from the app-only Application Support location to the existing App Group container. The app continues to own credentials, network refresh, and token handling. After a successful fetch it writes only the public contribution snapshot and reloads the Graph widget timeline. The widget extension reads this snapshot without credentials or network access.

The existing contribution graph layout remains the single rendering implementation. The widget uses the same seven-row layout and GitHub color ramp, but keeps the Graph widget's existing graph-only presentation. Missing or expired local snapshot data produces an empty graph rather than a fabricated account.

### Username preference

Add one App Group-backed `GitHubPreferences` value, defaulting to `true`. The GitHub settings page exposes a concise toggle. The in-app `GitHubContributionCard` reads the same preference and omits its username heading when disabled. The setting is device-local, like the other presentation settings, and does not enter habit data, iCloud records, or exports.

### Pro details

Change the unlocked branch of `MoreView.proSection` from a static row to a button that assigns `paywall = .settings`. Keep its active status text and identifier, and add a separate details identifier for the tappable state. `PaywallView` already renders the complete feature list and uses its unlocked footer when `Pro.isUnlocked` is true, so the opened sheet needs no new purchase logic.

## Failure and lifecycle behavior

- Disconnecting GitHub removes the credential and contribution cache; a configured GitHub Graph widget then displays the empty graph until another account connects.
- A refresh failure leaves the last valid snapshot available to the widget, matching the app card's cached behavior.
- A deleted habit falls back to the existing recommended habit behavior when a widget is configured for `Habit`.
- Toggling username visibility updates the app card immediately through the shared preference and does not affect GitHub authentication.
- Opening Pro details while unlocked never starts a purchase or restore request.

## Verification

- Unit tests cover the Graph widget source enum and provider selection, shared snapshot cache round trips, stale-cache retention, username preference defaults and round trips, and the unlocked Pro row contract.
- The focused test set must pass before the full suite.
- The complete iOS test suite and Release archive must pass.
- Simulator screenshots must show the GitHub settings toggle and the active Pro row opening the feature sheet.

