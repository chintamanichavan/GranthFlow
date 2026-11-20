# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Two unrelated projects in one repo

They share no code. Find out which one a task is about before touching anything.

1. **Anyfile / GranthFlow apps.** A C++20 engine (`src/` except `src/granthflow`) plus its platform apps:
   - the Mac and iOS apps (`mac/`)
   - Android (`android/`)
   - the PWA over WebAssembly (`web/`)
   - the CLI

   Code and folders use the name *Anyfile*. The product name shown to users is *GranthFlow*.
2. **granthflow web reader.** A single-user FastAPI + SQLite + epub.js EPUB reader (`src/granthflow/`, `pyproject.toml`,
   `data/`). It's meant to run behind Tailscale and has **no auth**.

`README.md` is the detailed reference for both: CLI commands, what the PDF and EPUB engines do and don't handle, routes, and schema.

## Check

`./check` builds and tests the engine (ctest: unit modules and end-to-end) and runs the Mac
app's unit tests. It takes about 25 s warm and 45 s from scratch.
- Exit codes: 0 green, 1 a test failed, 2 could not run.
- Commits run it through the pre-commit hook.
- `tests/test_check.sh` tests the script itself (about 2 min).
- Not covered: the Mac UI tests (Cmd-U in Xcode, needs Accessibility permission), iOS, Android, the PWA and the
  Python app. Use the commands below for those.

## Commands

```bash
# C++ engine + CLI (./check uses build/check; this is a separate manual build)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
(cd build && ctest -R unit_pdf)           # one module: tests are named unit_<module>; sources in tests/unit/<module>_test.cpp
./tests/run_tests.sh build/anyfile        # end-to-end only
python3 tests/bench.py build/anyfile      # timings on large generated files

# Web (PWA over WASM)
web/build.sh                              # needs the Emscripten SDK; output goes to web/vendor/ (committed on purpose)
python3 web/serve.py                      # http://127.0.0.1:8080
node tests/wasm/engine_smoke.mjs
.venv/bin/python -m pytest tests/test_pwa_browser.py

# Mac / iOS: open mac/Anyfile.xcodeproj; schemes are Anyfile (Mac) and GranthFlowiOS; Cmd-U runs the tests
# Android: cd android && ./gradlew assembleDebug | test | connectedAndroidTest

# granthflow web reader
.venv/bin/pip install -e ".[dev]" && .venv/bin/python -m playwright install chromium
.venv/bin/python -m granthflow.app        # http://127.0.0.1:8000; GRANTHFLOW_* env vars in README
.venv/bin/python -m pytest tests/test_api.py tests/test_epub_meta.py tests/test_autoimport.py tests/test_reader_browser.py
ruff check src tests && mypy src/granthflow   # mypy is strict
```

## Engine architecture: one facade, thin bindings

- **The facade.** `src/core/engine.hpp` is the only surface a platform sees: bytes in, bytes out, with no paths and no
  platform types. It exposes `detectKind`, `commandsForKind` and `runOnBytes`. Staging bytes to a temp file, filtering
  arguments and shaping results all happen there, once.
- **The bindings** only translate, and each is under 100 lines:

  | binding | file |
  |---|---|
  | CLI | `src/main.cpp` |
  | Mac/iOS (Obj-C++) | `mac/Shared/Bridge/AFEngine.mm` |
  | WASM (embind) | `src/wasm/engine_wasm.cpp` |
  | Android (JNI) | `android/app/src/main/cpp/engine_jni.cpp` |

  Never put parsing logic in a binding. A new capability belongs in a handler, and every platform then gets it.
- **Shared engine target.** Every platform builds the root `CMakeLists.txt` as a subdirectory and links the
  `anyfile_core` static library. A change to the engine therefore affects every app.
- **Handlers.** `src/handlers/` has one per file kind (text, markdown, pdf, epub, plus the byte-level base in
  `src/core`). They sit on the `src/pdf/` engine (lexer → parser → object model → xref/save) and the `src/epub/` engine
  (own zip reader/writer on zlib, XML tokenizer).
- **Write invariants:**
  - PDF edits are always **incremental updates**: the original bytes are never rewritten.
  - EPUB saves copy unchanged zip entries byte for byte and keep `mimetype` first and uncompressed.
  - In-place writes go through a temp file and a rename.
- **Mac/iOS layout.** `mac/Shared/` holds the Swift shared by both apps: document, `Engine.swift`, library, marks, covers,
  reading settings and intents. `mac/Anyfile/` is the Mac-only app and `mac/iOS/` the iOS app. Xcode folders are synced,
  so new files need no project edit.

## Cross-platform data contract

The Mac app writes `library.json` and `marks.json` to `~/Library/Application Support/Anyfile/`. The PWA
(`web/app/store.js`) keeps the same records in IndexedDB and imports and exports these exact files. When changing either side:
- New fields must be **additive only**, because Swift's decoder ignores unknown keys. The PWA adds `hash` (SHA-256) and stores only the file
  name in `path`.
- Write dates as ISO8601 **without fractional seconds**. Swift's `.iso8601` strategy rejects `.000Z`.
- On import, the later reading place wins and a mark is added only if its id is new.

## Gotchas

- `./check` builds in `build/check` and `build/check-mac`. If the older `build/` was configured under the folder's
  previous name (`Computer Science`), it no longer builds. Delete `build/CMakeCache.txt` and reconfigure.
- xcodebuild needs `unset SDKROOT` (`~/.zprofile` pins it to the Command Line Tools).
- xcodebuild prints a CoreSimulator "out-of-date" warning on this Mac. It doesn't affect macOS builds or tests.

## Git

Each platform is developed on its own branch (`ios`, `android`, `desktop`, …) and fast-forward merged into `master`.

## Design docs

`design/SYSTEM_DESIGN.md` and `design/OOP_DESIGN.md` cover the layers, data flows, class responsibilities and
extension points. The `design/blender_*.py` scripts are data-driven Blender renders (`blender -b -P <script> -- --render <png>`).
