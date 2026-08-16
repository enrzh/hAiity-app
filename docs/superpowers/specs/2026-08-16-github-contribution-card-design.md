# GitHub Contribution Card Design

## Purpose

hAiity can connect a GitHub account and show that account's official GitHub
contribution calendar as a read-only card on the Habits page. The integration
adds context to the GitHub-inspired visual language without turning GitHub into
a second sync system: habit data continues to sync only through private
CloudKit.

## User Experience

- Account connection lives in `Mehr > Über & Datenschutz > GitHub` so the
  existing order of the top-level More page does not change.
- The connection uses GitHub's browser-based device flow. hAiity displays the
  short code and opens GitHub's verification page; it never asks for a password.
- Once connected, a fixed GitHub card appears above all habits and reminders on
  the Habits page. It is not sortable and does not appear in Search.
- The card title is the exact username returned by GitHub. The contribution
  graph sits directly below it and uses GitHub's returned contribution levels.
- The card has no tap action, completion state, edit flow, swipe action, archive
  action, habit limit, reminder, calendar event, widget, or hAiity statistics.
- Holding the graph presents the same native lifted-preview interaction used by
  habit graphs. The menu contains one item: `GitHub-Profil öffnen` with the
  `arrow.up.right.square` symbol. Selecting it opens
  `https://github.com/<username>` in the default browser. Tapping the enlarged
  preview performs the same action.
- Disconnecting removes the token, cached username, and contribution data, and
  removes the card immediately.

## Data And Authentication

- Register one public GitHub OAuth client with Device Flow enabled. Its client
  ID is an application identifier, not a secret; no client secret ships.
- Request no repository scope. The integration reads the authenticated user's
  `viewer.login` and `viewer.contributionsCollection` through GitHub GraphQL.
  This includes public activity and only the private aggregate GitHub is willing
  to expose; hAiity never requests repository contents.
- Store the OAuth token only in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  It is neither exported nor mirrored through iCloud.
- Cache the username, contribution days, and fetch date as one Codable file in
  Application Support. Cache data is device-local and non-authoritative.
- Refresh on connection, when entering the foreground with data older than one
  hour, and through an explicit retry/refresh control in GitHub settings.
- A refresh failure keeps a valid cached card visible. If no cache exists, the
  settings page shows the error and the Habits page shows no broken placeholder.
- An authentication failure disconnects locally because the stored credential
  can no longer produce valid data.

## Boundaries

- Existing `CloudSync`, `HabitStore`, `HabitData`, imports, exports, widgets,
  StoreKit gates, and habit contribution grids are unchanged.
- The removed repository-sync implementation must not be restored. New GitHub
  types are read-only and cannot create repositories or push hAiity JSON.
- `ProGateTests.testGitHubIntegrationSurfaceStaysAbsent` is replaced by tests
  that enforce the read-only boundary: no `repo` scope, no mutation, no habit
  persistence, and no swipe actions on the GitHub card.
- GitHub is free functionality. It does not consume a free habit slot and is not
  gated by hAiity Pro.

## Privacy And Release

- The privacy policy and App Store review notes must describe the optional
  direct GitHub connection, local Keychain token, local cache, and disconnect.
- Re-evaluate the App Store privacy questionnaire against Apple's current
  definition of data collection before submission. Do not retain the existing
  `Data Not Collected` answer merely because hAiity has no backend.
- The app contains no GitHub SDK and no tracking. Network requests go directly
  from the device to `github.com` and `api.github.com`.
- Release configuration must fail clearly when the GitHub client ID is missing
  or still set to its placeholder.

## Verification

- Unit-test GraphQL decoding, contribution-level mapping, device-flow polling,
  cache freshness, cached-offline behavior, authentication failure, and full
  disconnect cleanup.
- Contract-test fixed list placement, the exact context-menu action, profile
  URL construction, no swipe attachment, and absence from Search.
- Add a debug fixture launch argument that renders a deterministic username and
  371-day graph without contacting GitHub.
- Build and run the app in an iPhone simulator. Inspect screenshots in light and
  dark mode with normal and compact views. Verify the hold preview and menu by
  interaction, not source inspection alone.
- Run the complete release gate and raise its test floor to the observed count.
