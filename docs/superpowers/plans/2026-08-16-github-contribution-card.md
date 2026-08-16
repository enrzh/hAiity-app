# GitHub Contribution Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, read-only GitHub account connection whose official contribution calendar appears as a fixed card on the Habits page.

**Architecture:** A `GitHubContributionStore` owns connection state, a device-local cache, and refresh policy. Focused Device Flow, Keychain, and GraphQL clients sit behind injected protocols for deterministic tests; `ContentView` observes the store and renders a dedicated `GitHubContributionCard` before normal habit rows.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, Security/Keychain, URLSession, GitHub OAuth Device Flow, GitHub GraphQL API, XCTest, existing `GraphContextMenu` and contribution-grid layout conventions.

## Global Constraints

- Minimum deployment target remains iOS 17.0; no third-party dependency or backend.
- The GitHub integration is read-only and requests no `repo` scope or repository permission.
- The OAuth token stays only in Keychain and never enters `HabitData`, export JSON, CloudKit, logs, diagnostics, or UserDefaults.
- The GitHub card is free, fixed above habits, absent from Search, and excluded from sorting, habit limits, widgets, stats, calendar, archive, and reminders.
- The card title is the exact GitHub username; the graph is directly below it.
- Holding the graph offers only `GitHub-Profil öffnen`; tapping the preview performs the same profile-opening action.
- No tap action and no leading, trailing, custom, full-swipe, or accessibility swipe action may be attached to the GitHub card.
- German remains the source language; every new visible string must have all 17 existing localizations before release.
- Re-read every target file immediately before editing because parallel sessions may change this worktree.

---

## File Map

- Create `Haiity/Services/GitHubCredentials.swift`: Keychain seam and production token vault.
- Create `Haiity/Services/GitHubDeviceFlow.swift`: request-code and polling state machine.
- Create `Haiity/Services/GitHubContributions.swift`: GraphQL request/response models and read-only client.
- Create `Haiity/Models/GitHubContributionStore.swift`: observable connection state, cache, refresh, and disconnect orchestration.
- Create `Haiity/Views/GitHubContributionCard.swift`: fixed card, graph rendering, and hold menu.
- Create `Haiity/Views/GitHubSettingsView.swift`: connect/code/waiting/connected/error/disconnect states.
- Modify `Haiity/Views/ContentView.swift`: own the store, refresh it, and insert the fixed card only in the Habits list.
- Modify `Haiity/Views/MoreView.swift`: expose GitHub under About & Privacy without changing top-level More order.
- Modify `Haiity/Views/HabitCard.swift`: move reusable context-menu types to a shared file only if compilation requires it; do not change habit behavior.
- Modify `Haiity/Localizable.xcstrings`, `Haiity/PrivacyInfo.xcprivacy`, `docs/store-listing.md`, and the public privacy page under `site/haiity/`.
- Modify `project.yml` and `tools/release.sh`: public client ID configuration and release validation.
- Create `HaiityTests/GitHubCredentialsTests.swift`, `HaiityTests/GitHubDeviceFlowTests.swift`, `HaiityTests/GitHubContributionsTests.swift`, `HaiityTests/GitHubContributionStoreTests.swift`, and `HaiityTests/GitHubCardContractTests.swift`.

### Task 1: Read-Only GitHub API Contract

**Files:**
- Create: `Haiity/Services/GitHubContributions.swift`
- Create: `HaiityTests/GitHubContributionsTests.swift`
- Modify: `HaiityTests/ProGateTests.swift:443`

**Interfaces:**
- Produces: `GitHubContributionDay`, `GitHubContributionSnapshot`, `GitHubContributionsClient`, `GitHubContributionsFetching`, shared `GitHubHTTPTransport`, and `URLSessionGitHubTransport`.
- Consumes: an OAuth bearer token supplied by later authentication work.

- [ ] **Step 1: Replace the obsolete absence gate with a failing read-only boundary test**

Assert that the source may contain `api.github.com` and `client_id`, but contains none of these mutation or broad-access markers:

```swift
let forbidden = ["scope=repo", "\"scope\": \"repo\"", "createRepository",
                 "deleteRepository", "git/refs", "contents_url", "haiity-data"]
for marker in forbidden {
    XCTAssertFalse(allGitHubSources.contains(marker), marker)
}
```

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:HaiityTests/ProGateTests/testGitHubIntegrationIsReadOnly
```

Expected: FAIL because the new test references source files that do not exist.

- [ ] **Step 2: Define contribution models and transport seams**

Implement these stable interfaces:

```swift
struct GitHubContributionDay: Codable, Equatable, Sendable, Identifiable {
    let date: String
    let count: Int
    let level: Int
    var id: String { date }
}

struct GitHubContributionSnapshot: Codable, Equatable, Sendable {
    let username: String
    let days: [GitHubContributionDay]
    let fetchedAt: Date
    var profileURL: URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "github.com"
        parts.path = "/\(username)"
        return parts.url
    }
}

protocol GitHubHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol GitHubContributionsFetching: Sendable {
    func fetch(token: String, now: Date) async throws -> GitHubContributionSnapshot
}
```

`URLSessionGitHubTransport` is the only live transport and delegates to
`URLSession.shared.data(for:)`, rejecting non-HTTP responses.
`GitHubContributionsClient.fetch` must POST only to `https://api.github.com/graphql`, query `viewer.login` plus `viewer.contributionsCollection(from:to:)`, flatten weeks chronologically, map `NONE...FOURTH_QUARTILE` to `0...4`, clamp negative counts to zero, and reject empty usernames, malformed dates, non-2xx responses, GraphQL errors, and duplicate dates.

- [ ] **Step 3: Test exact request and defensive decoding**

Add tests that verify the bearer header, `User-Agent: hAiity`, date variables, ordered flattening, five-level mapping, HTTP 401 classification, GraphQL error classification, and malformed payload rejection. The request body test must also assert it contains no mutation and no repository field.

Run the full `GitHubContributionsTests` class; expected: PASS.

- [ ] **Step 4: Commit the API contract**

```bash
git add Haiity/Services/GitHubContributions.swift \
  HaiityTests/GitHubContributionsTests.swift HaiityTests/ProGateTests.swift
git commit -m "Add read-only GitHub contribution client"
```

### Task 2: Device Flow And Keychain Credentials

**Files:**
- Create: `Haiity/Services/GitHubCredentials.swift`
- Create: `Haiity/Services/GitHubDeviceFlow.swift`
- Create: `HaiityTests/GitHubCredentialsTests.swift`
- Create: `HaiityTests/GitHubDeviceFlowTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `GitHubHTTPTransport` from Task 1.
- Produces: `GitHubCredentialVault`, `KeychainGitHubCredentialVault`, `GitHubDeviceCode`, `GitHubDeviceAuthorizing`, and `GitHubDeviceFlow`.

- [ ] **Step 1: Write failing vault and polling tests**

Cover save/read/delete, no token in error descriptions, request-code form fields, `authorization_pending`, `slow_down`, expiry, denial, cancellation, malformed JSON, and successful token return. Use an injected clock so tests perform no real sleeps.

- [ ] **Step 2: Implement a device-only Keychain vault**

Use service `com.aiity.haiity.github` and account `oauth-token`. Save with:

```swift
kSecClass: kSecClassGenericPassword
kSecAttrService: "com.aiity.haiity.github"
kSecAttrAccount: "oauth-token"
kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

Expose only:

```swift
protocol GitHubCredentialVault: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}
```

Never synchronize the item and never print the token or response body.

- [ ] **Step 3: Implement OAuth Device Flow without repository scope**

Use `https://github.com/login/device/code` and
`https://github.com/login/oauth/access_token`, JSON accept headers, and only
the public `client_id`. Do not send `scope=repo`; omit `scope` entirely. Expose:

```swift
struct GitHubDeviceCode: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresIn: Int
    let interval: Int
}

protocol GitHubDeviceAuthorizing: Sendable {
    func requestCode() async throws -> GitHubDeviceCode
    func pollForToken(_ code: GitHubDeviceCode) async throws -> String
}
```

- [ ] **Step 4: Configure the public client ID and release guard**

Add `GITHUB_CLIENT_ID` as a build setting and expose `GitHubClientID: $(GITHUB_CLIENT_ID)` in generated Info.plist. `GitHubAppConfig` reads and trims the key; debug builds may report an unconfigured state, while `tools/release.sh` must stop before archive if the resolved value is empty or `REPLACE_ME_CLIENT_ID`.

Register the production OAuth app in GitHub Developer Settings, enable Device Flow, and paste only its public client ID into project configuration. No client secret enters the repository.

- [ ] **Step 5: Run and commit authentication tests**

Run both new test classes; expected: PASS with no network calls and no sleeping.

```bash
git add project.yml tools/release.sh Haiity/Services/GitHubCredentials.swift \
  Haiity/Services/GitHubDeviceFlow.swift HaiityTests/GitHubCredentialsTests.swift \
  HaiityTests/GitHubDeviceFlowTests.swift
git commit -m "Add secure GitHub device authorization"
```

### Task 3: Connection State, Cache, And Refresh Policy

**Files:**
- Create: `Haiity/Models/GitHubContributionStore.swift`
- Create: `HaiityTests/GitHubContributionStoreTests.swift`

**Interfaces:**
- Consumes: `GitHubCredentialVault`, `GitHubDeviceAuthorizing`, and `GitHubContributionsFetching`.
- Produces: observable `GitHubContributionStore` used by settings and `ContentView`.

- [ ] **Step 1: Write failing orchestration tests**

Test boot from valid cache, stale refresh after one hour, no refresh before one hour, connect order (`request code -> poll -> fetch -> save token/cache`), failed first fetch leaving no token, cached network failure retaining the card, HTTP 401 deleting credentials/cache, concurrent refresh coalescing, and disconnect deleting both stores.

- [ ] **Step 2: Implement one observable source of truth**

Use this public shape:

```swift
@MainActor @Observable
final class GitHubContributionStore {
    enum Phase: Equatable { case disconnected, connecting, connected, failed(String) }
    private(set) var phase: Phase = .disconnected
    private(set) var deviceCode: GitHubDeviceCode?
    private(set) var snapshot: GitHubContributionSnapshot?

    init(vault: GitHubCredentialVault = KeychainGitHubCredentialVault(),
         authorizer: GitHubDeviceAuthorizing = GitHubDeviceFlow(),
         contributions: GitHubContributionsFetching = GitHubContributionsClient(),
         cacheURL: URL = GitHubContributionStore.defaultCacheURL)

    func boot(now: Date = .now) async
    func connect() async
    func refresh(now: Date = .now, forced: Bool = false) async
    func disconnect()
}
```

Persist one `GitHubContributionSnapshot` JSON file beside other device-local Application Support data, atomically. The cache is never merged with habit data. Coalesce overlapping refreshes into one task and classify only 401/bad-credential responses as disconnects.

- [ ] **Step 3: Add a deterministic debug fixture**

When `-demo-github-card` is present in DEBUG, load username `enrzh` and 371 deterministic days locally. Do not read Keychain or contact GitHub. Production compilation must exclude this branch.

- [ ] **Step 4: Run tests and commit**

```bash
git add Haiity/Models/GitHubContributionStore.swift \
  HaiityTests/GitHubContributionStoreTests.swift
git commit -m "Add GitHub contribution connection state"
```

### Task 4: Settings And Habit-Page Card

**Files:**
- Create: `Haiity/Views/GitHubSettingsView.swift`
- Create: `Haiity/Views/GitHubContributionCard.swift`
- Create: `HaiityTests/GitHubCardContractTests.swift`
- Modify: `Haiity/Views/ContentView.swift`
- Modify: `Haiity/Views/MoreView.swift`
- Modify: `Haiity/Views/HabitCard.swift` only if moving `GraphContextMenu` to its own shared file is necessary.

**Interfaces:**
- Consumes: `GitHubContributionStore.snapshot`, `.phase`, `.connect()`, `.refresh()`, and `.disconnect()`.
- Produces: accessible settings and one fixed Habit-page row with no habit actions.

- [ ] **Step 1: Write failing placement and interaction contracts**

Assert all of the following:

```swift
XCTAssertTrue(content.contains("GitHubContributionCard"))
XCTAssertTrue(card.contains("GitHub-Profil öffnen"))
XCTAssertTrue(card.contains("arrow.up.right.square"))
XCTAssertFalse(card.contains("SwipeRevealPan"))
XCTAssertFalse(card.contains("swipeActions"))
XCTAssertFalse(card.contains("RevealAction"))
XCTAssertFalse(searchListSource.contains("GitHubContributionCard"))
```

Also test `https://github.com/<percent-encoded-login>` construction and verify the GitHub row is outside the habit `ForEach` and before it.

- [ ] **Step 2: Build the connection settings**

Add `case github` to `MoreRoute`. Change the About destination to
`AboutView(github: github)` and add a `GitHub` navigation row inside its
privacy list; `moreDestination(.github)` must construct
`GitHubSettingsView(store: github)`. Pass this same `GitHubContributionStore`
reference through both native and fallback More routes, preserving the exact
top-level More order. The destination has compact native states:

- Disconnected: `GitHub verbinden`.
- Connecting: visible user code, `Auf GitHub öffnen`, and progress.
- Connected: username, `Aktualisieren`, and destructive `Verbindung trennen`.
- Failed: one concise error and `Erneut versuchen`.

Opening GitHub uses `UIApplication.shared.open` only after validating an HTTPS URL. Disconnect requires confirmation. Add accessibility identifiers `open-github-settings`, `github-connect`, `github-open-verification`, `github-refresh`, and `github-disconnect`.

- [ ] **Step 3: Build a dedicated contribution card**

Create a view that takes only immutable display data and one profile callback:

```swift
struct GitHubContributionCard: View, Equatable {
    let snapshot: GitHubContributionSnapshot
    let collapsed: Bool
    let openProfile: () -> Void
}
```

Render the username as the header and a stable 7-row contribution grid below. Reuse Theme spacing, corner radius, dynamic type behavior, RTL chronology rules, and GitHub level colors, but do not construct a fake `Habit`. Attach `GraphContextMenu` only to the graph bounds with exactly one `GraphMenuAction`; both that action and `commit` call `openProfile`.

- [ ] **Step 4: Insert the fixed card into the Habits page only**

Own `@State private var github = GitHubContributionStore()` in `ContentView`. In `habitList`, render the card before the normal `ForEach` when `snapshot != nil`, with standard list insets/background and no `.onMove`, `.swipeActions`, or `row(for:)`. Treat a connected snapshot as content so an account with zero habits sees the list rather than the habit empty state. Do not add it to `searchList` or `filteredHabits`.

Call `await github.boot()` from the existing root task and `await github.refresh()` when the scene becomes active; the one-hour policy prevents unnecessary requests.

- [ ] **Step 5: Run focused tests and commit**

Run `GitHubCardContractTests`, existing `GesturePerfTests`, `StatsAndReorderTests`, and search-state tests. Expected: PASS, with existing habit hold/swipe behavior unchanged.

```bash
git add Haiity/Views/GitHubSettingsView.swift \
  Haiity/Views/GitHubContributionCard.swift Haiity/Views/ContentView.swift \
  Haiity/Views/MoreView.swift Haiity/Views/HabitCard.swift \
  HaiityTests/GitHubCardContractTests.swift
git commit -m "Show GitHub contributions on the Habits page"
```

### Task 5: Localization, Privacy, And Store Disclosure

**Files:**
- Modify: `Haiity/Localizable.xcstrings`
- Modify: `Haiity/PrivacyInfo.xcprivacy`
- Modify: `docs/store-listing.md`
- Modify: `site/haiity/privacy.html` or the actual deployed privacy source found by `rg --files site/haiity`.

**Interfaces:**
- Consumes: final visible strings and network behavior from Tasks 1-4.
- Produces: accurate user and App Review disclosure.

- [ ] **Step 1: Add all 17 localizations**

Add concise translations for GitHub settings, connection states, refresh, disconnect confirmation, errors, and `GitHub-Profil öffnen`. Run the repository localization parity tests and verify no language falls back to German.

- [ ] **Step 2: Update privacy and review material**

State plainly that connection is optional; authentication and contribution requests go directly to GitHub; the OAuth token stays in device-only Keychain; the contribution cache stays on device; disconnect deletes both; hAiity receives nothing on a developer server. Remove the old blanket review statement that the app communicates only with iCloud.

Audit Apple's current App Privacy questionnaire definitions against this exact flow. Record the selected answers in `docs/store-listing.md`; do not guess and do not silently preserve `Data Not Collected` if Apple's definition requires disclosure of identifiers or usage data handled by an integrated third party.

- [ ] **Step 3: Validate manifests and commit**

Run privacy-manifest and store-listing tests. Confirm `NSPrivacyTracking` remains false, no GitHub SDK signature exists, and required-reason APIs remain accurate.

```bash
git add Haiity/Localizable.xcstrings Haiity/PrivacyInfo.xcprivacy \
  docs/store-listing.md site/haiity
git commit -m "Document GitHub connection privacy"
```

### Task 6: Runtime And Release Verification

**Files:**
- Modify: `tools/release.sh`
- Modify: only files implicated by observed runtime defects.

**Interfaces:**
- Consumes: complete GitHub integration.
- Produces: screenshot-verified UI and a passing release gate with an honest test floor.

- [ ] **Step 1: Generate the project and run the complete test suite**

Run the repository's project-generation command if `project.yml` changed, then:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project Haiity.xcodeproj -scheme Haiity \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: all tests PASS. Capture the executed test count and raise `MIN_TESTS` in `tools/release.sh` to that exact count; never lower it.

- [ ] **Step 2: Inspect the real UI in light and dark mode**

Launch with `-demo-github-card`, capture screenshots at standard and accessibility text sizes in both appearances, and inspect them. Verify title truncation, 7-row graph geometry, first/last day framing, list insets, compact mode, RTL chronology, and that the card does not overlap native navigation chrome.

- [ ] **Step 3: Exercise the interaction**

Long-press the graph in the simulator. Confirm the lifted preview fits the GitHub card, the menu has exactly `GitHub-Profil öffnen`, the menu action opens the expected HTTPS profile, tapping the preview does the same, normal tapping does nothing, and horizontal swiping neither reveals actions nor moves the card.

- [ ] **Step 4: Exercise a real GitHub connection**

Using a non-production test account, complete device authorization, compare the rendered date/count levels against that GitHub profile, relaunch offline to confirm cached rendering, reconnect the network and refresh, then disconnect and confirm Keychain/cache/card removal. Never record or paste the access token.

- [ ] **Step 5: Run the release gate and commit verification fixes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./tools/release.sh
```

Expected: archive validation passes, test count is at or above the new floor, production client ID is configured, no secrets are found, and no upload occurs without an explicit later instruction.

```bash
git add tools/release.sh
git commit -m "Verify GitHub contribution card release gate"
```
