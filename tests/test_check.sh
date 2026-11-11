#!/bin/bash
# Tests for ./check (exit 0 green, 1 a test failed, 2 could not run). Red cases run on a
# copy of the tracked files, so the real tree is never touched. Takes about 2 minutes:
# each copy builds the engine and the Mac app from scratch.
D=$(cd "$(dirname "$0")/.." && pwd)
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
# expect NAME WANT_EXIT OUTPUT_MUST_CONTAIN -- COMMAND...
expect() {
  local name=$1 want=$2 needle=$3; shift 4
  out=$("$@" 2>&1); code=$?
  [ "$code" = "$want" ] || { bad "$name: exit $code, want $want"; printf '%s\n' "$out" | tail -8; return; }
  [ -z "$needle" ] || printf '%s' "$out" | grep -qF -- "$needle" || { bad "$name: output lacks '$needle'"; return; }
  ok "$name"
}
copy() {
  local c; c=$(mktemp -d)
  (cd "$D" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -cf -) | (cd "$c" && tar xf -)
  echo "$c"
}

expect "green from any cwd" 0 "ok   mac" -- sh -c "cd / && '$D/check'"
printf '%s' "$out" | grep -q Terminated && bad "green run prints job-control noise" || ok "green run is quiet"

c=$(copy)
printf '\nadd_test(NAME planted_failure COMMAND false)\n' >> "$c/CMakeLists.txt"
expect "a failing engine test exits 1" 1 "FAIL engine" -- "$c/check"

# A failing Mac unit test fails the check too (its result comes through a pipe).
c2=$(copy)
printf 'import XCTest\nfinal class PlantedTests: XCTestCase { func testPlanted() { XCTFail("planted") } }\n' > "$c2/mac/AnyfileTests/PlantedTests.swift"
expect "a failing Mac test exits 1" 1 "FAIL mac" -- "$c2/check"
rm -rf "$c2"

# Missing tool: a PATH without cmake.
nocm=$(mktemp -d); for t in bash sh env git xcodebuild xcrun dirname mktemp sleep kill; do ln -s "$(command -v $t)" "$nocm/$t"; done
expect "a missing tool exits 2" 2 "cmake not found" -- env CHECK_TEST=1 CHECK_PATH="$nocm" "$c/check"
rm -rf "$nocm"

# A hung suite is stopped by check's own limit and leaves nothing running.
printf '\nadd_test(NAME planted_hang COMMAND sleep 37)\n' >> "$c/CMakeLists.txt"
expect "a hung suite exits 2" 2 "did not finish" -- env CHECK_TEST=1 CHECK_LIMIT=20 "$c/check"
pgrep -qx -f 'sleep 37' && bad "hung suite left running" || ok "hung suite is killed"
rm -rf "$c"

[ "$fail" = 0 ] && echo "all passed"
exit "$fail"
