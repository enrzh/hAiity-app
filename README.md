# hAiity

Habits, GitHub style. A native iOS habit tracker where every habit is a
contribution graph — check in, paint a square.

**No server. No account. No tracking.** Your habits live on your iPhone, in a
plain JSON file inside the app group (the widget reads that same file). If the
device is signed into iCloud, hAiity mirrors that file into **your own private
iCloud** — one record in the CloudKit private database of your Apple ID.
Nothing to set up, no sign-in inside the app, no server of ours anywhere in the
path. We never see the data.

Signed out of iCloud, or offline? Local habit tracking remains available.
Sync status and recovery controls live in Behavior & Sharing.

- SwiftUI, iOS 18+, German-first with 17 UI localizations
- Per-habit daily reminders + evening summary (permission asked only when
  you enable one — never at launch)
- Home Screen and Lock Screen widgets, plus a Control Center control
- Local-first; iCloud is a mirror with union-merge (a check-in anywhere
  counts, a conflict can never delete a day)
- Export / import JSON at any time — an import merges, it never overwrites
- `docs/` (live: https://enrzh.github.io/hAiity/) is a static web prototype of
  the same idea; it stores everything in the browser and talks to nothing

Build with the pinned XcodeGen 2.46.0: `bash tools/generate-project.sh`.
The optional on-device sentence reader uses MLX and tokenizer packages pinned
in `project.yml` and `Package.resolved`. No model weights ship in the app.

[Development, architecture, tests and releases](docs/development.md) is the
current engineering guide. [The design system](docs/design/haiity-ui-design-system.md)
owns UI conventions. Dated files under `docs/plans/` and `docs/superpowers/`
are historical records, not current build or release instructions.

Part of the [aiity](https://aiity.de) family.
