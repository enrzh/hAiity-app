# hAiity

Habits, GitHub style. A native iOS habit tracker where every habit is a
contribution graph — check in, paint a square.

**No server. No account. No tracking.** Your habits live on your iPhone, in a
plain JSON file inside the app group (the widget reads that same file). If the
device is signed into iCloud, hAiity mirrors that file into **your own private
iCloud** — one record in the CloudKit private database of your Apple ID.
Nothing to set up, no sign-in inside the app, no server of ours anywhere in the
path. We never see the data.

Signed out of iCloud, or offline? The app works exactly the same; the status
row under "Mehr" says so instead of pretending. Nothing is lost, and it syncs
again when it can.

- SwiftUI, iOS 17+, German-first with 16 languages
- Per-habit daily reminders + evening summary (permission asked only when
  you enable one — never at launch)
- Home-screen widget (small + medium)
- Local-first; iCloud is a mirror with union-merge (a check-in anywhere
  counts, a conflict can never delete a day)
- Export / import JSON at any time — an import merges, it never overwrites
- `docs/` (live: https://enrzh.github.io/hAiity/) is a static web prototype of
  the same idea; it stores everything in the browser and talks to nothing

Build: `xcodegen generate && open Haiity.xcodeproj` (XcodeGen, no other
dependencies). Part of the [aiity](https://aiity.de) family.
