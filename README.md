# hAiity

Habits, GitHub style. A native iOS habit tracker where every habit is a
contribution graph — check in, paint a square.

**No server. No account. No tracking.** Data lives on your device, and
optionally in a private `haiity-data` repo in **your own** GitHub account,
written via the GitHub Contents API with a fine-grained token that never
leaves your Keychain. Every check-in is a real commit — your streak lights
your actual contribution graph.

- SwiftUI, iOS 17+, German-first with 16 languages
- Per-habit daily reminders + evening summary (permission asked only when
  you enable one — never at launch)
- Home-screen widget (small + medium)
- Offline-first; GitHub sync is a mirror with union-merge (a check-in
  anywhere counts, conflicts can never delete a day)
- `docs/` (live: https://enrzh.github.io/hAiity/) contains a static web prototype of the same concept

Build: `xcodegen generate && open Haiity.xcodeproj` (XcodeGen, no other
dependencies). Part of the [aiity](https://aiity.de) family.
