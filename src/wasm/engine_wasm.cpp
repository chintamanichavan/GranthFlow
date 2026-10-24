// WebAssembly face of the C++ engine. JavaScript sees only strings, arrays and Uint8Arrays.
// The shape matches mac/Anyfile/Bridge/AFEngine.h on purpose: both are translation only, and the
// work happens in anyfile::detectKind / commandsForKind / runOnBytes.
#include <emscripten/bind.h>
#include <emscripten/val.h>

#include <string>
#include <vector>

#include "core/engine.hpp"

using emscripten::val;

namespace {

/// A Uint8Array (or any array of numbers) as bytes the engine can work on.
std::string toBytes(const val& array) {
    const std::vector<uint8_t> v = emscripten::convertJSArrayToNumberVector<uint8_t>(array);
    return std::string(reinterpret_cast<const char*>(v.data()), v.size());
}

/// Bytes as a Uint8Array owned by JavaScript, copied out of the heap so growth cannot move it.
val toUint8Array(const std::string& s) {
    val out = val::global("Uint8Array").new_(s.size());
    out.call<void>("set", val(emscripten::typed_memory_view(s.size(), reinterpret_cast<const uint8_t*>(s.data()))));
    return out;
}

std::vector<std::string> toStrings(const val& array) {
    const unsigned n = array["length"].as<unsigned>();
    std::vector<std::string> out;
    out.reserve(n);
    for (unsigned i = 0; i < n; ++i) out.push_back(array[i].as<std::string>());
    return out;
}

std::string detectKind(const val& bytes, const std::string& name) {
    return anyfile::detectKind(toBytes(bytes), name);
}

val commandsForKind(const std::string& kind) {
    val out = val::array();
    unsigned i = 0;
    for (const auto& c : anyfile::commandsForKind(kind)) {
        val entry = val::object();
        entry.set("name", c.name);
        entry.set("usage", c.usage);
        entry.set("help", c.help);
        out.set(i++, entry);
    }
    return out;
}

val run(const std::string& command, const val& args, const val& bytes, const std::string& name, const std::string& kind) {
    const anyfile::RunResult r = anyfile::runOnBytes(command, toStrings(args), toBytes(bytes), name, kind);
    val out = val::object();
    out.set("status", static_cast<int>(r.status));
    out.set("output", r.output);
    out.set("error", r.error);
    out.set("didChange", r.didChange);
    // `changed` is absent unless the command rewrote the file, so a caller can test it directly.
    if (r.didChange) out.set("changed", toUint8Array(r.changed));
    // The output as bytes too, for commands such as `cat` whose output is not text.
    out.set("outputData", toUint8Array(r.output));
    return out;
}

}  // namespace

EMSCRIPTEN_BINDINGS(anyfile) {
    emscripten::function("detectKind", &detectKind);
    emscripten::function("commandsForKind", &commandsForKind);
    emscripten::function("run", &run);
}
