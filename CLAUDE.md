# anyfile / GranthFlow

Two apps sharing one repo and no code (see README): the Anyfile C++20 engine with its SwiftUI
Mac app (GranthFlow), and the granthflow Python web reader in `src/granthflow`.

## Check
`./check` builds and tests the engine (ctest: unit modules and end-to-end) and runs the Mac
app's unit tests. About 25 s warm, 45 s from scratch. Exit 0 green, 1 a test failed, 2 could
not run. Commits run it through the pre-commit hook. `tests/test_check.sh` tests it (~2 min).
Not covered: the Mac UI tests (Cmd-U in Xcode, need Accessibility permission) and the Python app.

## Layout
- `src/` engine (except `src/granthflow`, the Python app), `tests/` engine tests and bench
- `mac/` Xcode project; folders are synced, so new files need no project edit
- `design/` system and OOP design documents

## Gotchas
- `./check` builds in `build/check` and `build/check-mac`. The older `build/` was configured
  under the folder's previous name (`Computer Science`) and no longer builds; reconfigure it
  with `cmake -S . -B build` after deleting `build/CMakeCache.txt` if you need it.
- xcodebuild needs `unset SDKROOT` (`~/.zprofile` pins it to the Command Line Tools).
- xcodebuild prints a CoreSimulator "out-of-date" warning on this Mac; it does not affect macOS
  builds or tests.
