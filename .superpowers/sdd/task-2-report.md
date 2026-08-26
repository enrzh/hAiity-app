# Task 2 Report: Pro Policy, App Lifecycle, and Scoped Gates

## Status

DONE_WITH_CONCERNS

## Commit SHA(s)

- `5ff27436fe4c527e78d0ed8d25658f7ef3db54bc` — `fix: reapply pro-gated sync preferences live`

## Worktree / Baseline

- Isolated worktree: `/Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy`
- Branch: `codex/task2-pro-policy`
- Baseline commit: `f17b985` (`Prepare hAiity build 106`)

## Scope Owned

- `Haiity/Views/ContentView.swift`
- `HaiityTests/ProGateTests.swift`

No native sync internals, CloudSync internals, theme appearance controls, widgets, notification services, release files, plan files, or other `.superpowers` artifacts were edited.

## Files Changed

- `Haiity/Views/ContentView.swift`
- `HaiityTests/ProGateTests.swift`

## What Changed

- Added a focused Task 2 regression test that requires the root entitlement observer to reapply shared cloud preferences when the live Pro entitlement changes.
- Updated the existing `ContentView` `.onChange(of: proStatus.unlocked)` handler to call `applyCloudPreferences()` immediately before handling the downgrade paywall path.

## Why

- The branch already contained the major Task 2 Pro-gating work from the brief: shared `ProGate` policy, visible-habit limiting, service-side Pro checks, downgrade refresh hooks, and the active entitlement monitor.
- One remaining gap was that an entitlement change updated the paywall state, but did not immediately re-derive the device-local paid sync toggles from the shared cloud preferences in the root lifecycle path.
- This patch keeps the root lifecycle in sync with the existing Pro policy without adding a new entitlement abstraction or touching sync internals.

## Exact Commands / Results

1. Read the brief:

   - Command:

     ```bash
     sed -n '1,240p' /Users/enrico/Documents/GitHub/haiity/.superpowers/sdd/task-2-brief.md
     ```

   - Result: confirmed the Task 2 scope was limited to Pro policy, app lifecycle, and the listed views/services/tests.

2. Verified the main checkout was dirty and created an isolated worktree:

   - Commands:

     ```bash
     git -C /Users/enrico/Documents/GitHub/haiity worktree list
     git -C /Users/enrico/Documents/GitHub/haiity check-ignore -v .worktrees
     git -C /Users/enrico/Documents/GitHub/haiity worktree add /Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy -b codex/task2-pro-policy f17b985
     ```

   - Results:
     - Main checkout had unrelated dirty files and was not used for implementation.
     - `.worktrees/` is ignored by Git.
     - New isolated worktree created successfully on branch `codex/task2-pro-policy`.

3. Audited the Task 2 Pro surface in the isolated worktree:

   - Commands included:

     ```bash
     rg -n "Pro\.isUnlocked|ProStatus|ProGate|freeHabitLimit|Paywall|calendarSync|nativeReminderSync|HabitVisibility|isUnlocked|unlock" ...
     sed -n '1,260p' Haiity/Models/ProEntitlement.swift
     sed -n '1,420p' HaiityTests/ProGateTests.swift
     sed -n '1,320p' Haiity/Views/StatsView.swift
     sed -n '1,360p' Haiity/Views/MoreView.swift
     sed -n '1,320p' Haiity/Views/EditHabitSheet.swift
     sed -n '1,260p' Haiity/Views/ArchiveView.swift
     sed -n '2580,2645p' Haiity/Views/ContentView.swift
     sed -n '2748,2785p' Haiity/Views/ContentView.swift
     ```

   - Result: confirmed most Task 2 brief requirements were already present in the baseline branch.

4. RED check before the production change:

   - Command:

     ```bash
     python3 - <<'PY'
     from pathlib import Path
     text = Path('/Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy/Haiity/Views/ContentView.swift').read_text()
     start = text.index('.onChange(of: proStatus.unlocked)')
     end = text.index('.onChange(of: showAdd)', start)
     block = text[start:end]
     if 'applyCloudPreferences()' in block:
         print('unexpected pass: applyCloudPreferences already present')
         raise SystemExit(1)
     print('expected red: applyCloudPreferences missing from proStatus change block')
     raise SystemExit(2)
     PY
     ```

   - Result: exited with status `2` and printed `expected red: applyCloudPreferences missing from proStatus change block`.

5. Generated the Xcode project and performed the available non-device build check before and after the patch:

   - Commands:

     ```bash
     xcodegen generate
     xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
     ```

   - Results:
     - `xcodegen generate` succeeded and created `Haiity.xcodeproj`.
     - `xcodebuild build-for-testing ...` succeeded before the patch with `** TEST BUILD SUCCEEDED **`.
     - `xcodebuild build-for-testing ...` succeeded again after the patch with `** TEST BUILD SUCCEEDED **`.

6. GREEN check after the production change:

   - Command:

     ```bash
     python3 - <<'PY'
     from pathlib import Path
     text = Path('/Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy/Haiity/Views/ContentView.swift').read_text()
     start = text.index('.onChange(of: proStatus.unlocked)')
     end = text.index('.onChange(of: showAdd)', start)
     block = text[start:end]
     assert 'applyCloudPreferences()' in block
     print('green: applyCloudPreferences present in proStatus change block')
     PY
     ```

   - Result: printed `green: applyCloudPreferences present in proStatus change block`.

7. Reviewed the diff and committed:

   - Commands:

     ```bash
     git -C /Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy diff --stat
     git -C /Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy add Haiity/Views/ContentView.swift HaiityTests/ProGateTests.swift
     git -C /Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy commit -m "fix: reapply pro-gated sync preferences live"
     git -C /Users/enrico/Documents/GitHub/haiity/.worktrees/task-2-pro-policy rev-parse HEAD
     ```

   - Results:
     - Diff stat before commit:

       ```text
        Haiity/Views/ContentView.swift |  1 +
        HaiityTests/ProGateTests.swift | 11 +++++++++++
        2 files changed, 12 insertions(+)
       ```

     - Commit succeeded.
     - Final commit SHA: `5ff27436fe4c527e78d0ed8d25658f7ef3db54bc`

## Test Summary

- Added one focused regression test in `HaiityTests/ProGateTests.swift`.
- Ran a RED source-contract check for the missing lifecycle hook.
- Ran a GREEN source-contract check after the patch.
- Ran `xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` successfully after the patch.

## Concerns

- Per instruction, I did not create or use any simulator and did not use the device hub.
- Because of that constraint, I did not run `xcodebuild test` against `HaiityTests/ProGateTests` and did not perform the physical-phone “toggle debug entitlement off while gated pages are open” verification from the brief.
- Status is therefore `DONE_WITH_CONCERNS`, not `DONE`: the scoped code change is implemented, compiled in a non-device build-for-testing pass, and backed by a focused regression test plus RED/GREEN contract checks, but live runtime behavior on a device remains unverified in this turn.
