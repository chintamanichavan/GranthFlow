#!/bin/sh
# Builds the C++ engine to WebAssembly and puts it in web/vendor/.
#
#   web/build.sh            release, what the PWA ships
#   web/build.sh debug      assertions on, names kept, for tracking a crash down
#
# Needs the Emscripten SDK. Install it once:
#
#   git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
#   ~/emsdk/emsdk install latest && ~/emsdk/emsdk activate latest
#
# This script finds it at $EMSDK, ~/emsdk or /usr/local/emsdk, or takes emcc from the PATH.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-release}

if ! command -v emcmake >/dev/null 2>&1; then
  for candidate in ${EMSDK:-} "$HOME/emsdk" /usr/local/emsdk /opt/emsdk; do
    if [ -n "$candidate" ] && [ -f "$candidate/emsdk_env.sh" ]; then
      # shellcheck disable=SC1091
      . "$candidate/emsdk_env.sh" >/dev/null 2>&1
      break
    fi
  done
fi

if ! command -v emcmake >/dev/null 2>&1; then
  echo "emcmake not found. Install the Emscripten SDK, then run this again:" >&2
  echo "  git clone https://github.com/emscripten-core/emsdk.git ~/emsdk" >&2
  echo "  ~/emsdk/emsdk install latest && ~/emsdk/emsdk activate latest" >&2
  exit 1
fi

build="$root/build-wasm"
if [ "$mode" = debug ]; then
  build="$root/build-wasm-debug"
  type=Debug
else
  type=Release
fi

emcmake cmake -S "$root" -B "$build" -DCMAKE_BUILD_TYPE="$type" >/dev/null
cmake --build "$build" -j

echo
ls -lh "$root/web/vendor/anyfile.mjs" "$root/web/vendor/anyfile.wasm" | awk '{print $9, $5}'
echo
echo "Serve it:   python3 web/serve.py"
echo "Check it:   node tests/wasm/engine_smoke.mjs"
