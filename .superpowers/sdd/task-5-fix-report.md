# Task 5 corrective fix report

## Status

- Corrective implementation completed in isolated worktree `/Users/enrico/Documents/GitHub/haiity/.worktrees/task-5-corrective`.
- Small pure widget contract added so a missing GitHub snapshot maps to the connect prompt path, while a valid empty snapshot maps to graph content.
- `GraphWidgetView` and `GitHubWidgetGraph` now consume that explicit content state.
- Focused widget test coverage was extended in the existing widget test files.
- Physical validation from the original Task 5 brief is still pending.

## Commit SHAs

- Base Task 5 branch head on entry: `6162ee188fc0fcc3b7d82afcb30d2ca816c97117`
- Referenced prior Task 5 change: `210fc2d`
- Corrective commit: pending at report write time

## Files changed

- `HaiityWidget/WidgetLogic.swift`
- `HaiityWidget/GraphWidgetView.swift`
- `HaiityWidget/GitHubWidgetGraph.swift`
- `HaiityTests/WidgetLogicTests.swift`
- `HaiityTests/GitHubWidgetTests.swift`

## Exact commands and results

1. Read the brief and inspected the cited commits.
   - `cat /Users/enrico/Documents/GitHub/haiity/.superpowers/sdd/task-5-brief.md`
   - `git -C /Users/enrico/Documents/GitHub/haiity show --stat --oneline 6162ee1`
   - `git -C /Users/enrico/Documents/GitHub/haiity show --stat --oneline 210fc2d`
   - Result: `6162ee1` only documented Task 5 work; `210fc2d` changed widget logic/tests for empty GitHub handling.

2. Created an isolated workspace and moved it onto the Task 5 branch.
   - `git -C /Users/enrico/Documents/GitHub/haiity worktree add /Users/enrico/Documents/GitHub/haiity/.worktrees/task-5-corrective -b task-5-corrective`
   - `git -C /Users/enrico/Documents/GitHub/haiity/.worktrees/task-5-corrective checkout -B task-5-corrective codex/task5-widget-coverage`
   - Result: isolated worktree created and aligned to `6162ee1` with `210fc2d` in history.

3. Generated the local Xcode project in the isolated worktree.
   - `cd /Users/enrico/Documents/GitHub/haiity/.worktrees/task-5-corrective && xcodegen generate`
   - Result: created `Haiity.xcodeproj`.

4. Red step: ran the focused widget tests before implementing the new contract.
   - `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests CODE_SIGNING_ALLOWED=NO`
   - Result: build failed as expected with the new missing-symbol contract failures:
     - `Type 'WidgetLogic' has no member 'gitHubWidgetContent'`
     - `Type 'Equatable' has no member 'connectPrompt'`
     - `Type 'Equatable' has no member 'graph'`

5. Implemented the corrective change.
   - Added `GitHubWidgetContent` and `WidgetLogic.gitHubWidgetContent(...)`.
   - Routed `GraphWidgetView` through the new helper.
   - Switched `GitHubWidgetGraph` to explicit `connectPrompt` vs `graph(days:)` rendering.
   - Added focused tests in `HaiityTests/WidgetLogicTests.swift` and `HaiityTests/GitHubWidgetTests.swift`.

6. Verification run against the connected phone with signing disabled.
   - `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests CODE_SIGNING_ALLOWED=NO`
   - Result: production code compiled past the new contract, but install failed because the unsigned app could not be installed on device (`0xe800801c`, no code signature found).

7. Verification run against the connected phone with automatic signing.
   - `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Haiity.xcodeproj -scheme Haiity -destination 'id=00008150-000120AC0287801C' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests DEVELOPMENT_TEAM=H8FW6W6K2D CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates`
   - Result: app installed and tests launched, but the focused widget suite still failed for existing environment-dependent reasons unrelated to this corrective contract:
     - several source-contract tests try to open workspace source files by absolute host path from the device test process and get `Code=260` file-not-found
     - `WidgetRenderingTests.testAffectedWidgetsRenderInspectableLightModeImages` failed writing `/tmp/haiity-roster-large.png` with `Code=513` permission denied
     - the new GitHub content contract itself was no longer the failing build blocker

8. Available non-simulator verification that succeeded.
   - `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build-for-testing -project Haiity.xcodeproj -scheme Haiity -destination 'generic/platform=iOS' -only-testing:HaiityTests/WidgetLogicTests -only-testing:HaiityTests/WidgetRenderingTests -only-testing:HaiityTests/GitHubWidgetTests CODE_SIGNING_ALLOWED=NO`
   - Result: `** TEST BUILD SUCCEEDED **`

## Concerns

- Required physical validation from the original Task 5 brief remains pending. I did not perform on-device widget interaction validation after a cold app launch.
- The focused widget tests are not fully device-safe today because multiple existing tests read source files from host paths and one writes to `/tmp`; those environment assumptions still block a full green device run even after this corrective change.
- The compile-level focused verification succeeded, but the run-level focused verification remains limited by the existing test harness and the still-pending physical validation gate.
