// The engine as a platform sees it: bytes in, bytes out, no file paths and no platform types.
// Every binding (the SwiftUI app's Objective-C++ bridge, the WebAssembly build, and whatever
// platform comes next) is a thin wrapper over these three calls, so the staging of bytes into
// a file the handlers can work on, the argument filtering and the result shaping are written
// once here rather than once per platform.
#pragma once
#include <string>
#include <vector>

#include "handler.hpp"

namespace anyfile {

/// What running one command did.
struct RunResult {
    Status status = Status::Error;
    std::string output;      // what the command printed
    std::string error;       // why it failed, empty when it did not
    std::string changed;     // the file's new bytes, meaningful only when `didChange`
    bool didChange = false;  // whether the command rewrote the file
};

/// "pdf", "epub", "markdown", "text" or "binary", from magic bytes, the name's extension and content.
std::string detectKind(const std::string& bytes, const std::string& name);

/// Commands for a kind: the kind's own, followed by the ones every file has.
std::vector<Command> commandsForKind(const std::string& kind);

/// Runs one command against in-memory contents. The bytes are staged in a private temporary
/// directory, the handler runs on them, and the result carries the new bytes if they changed.
/// `kind` may be empty to detect it. `--out`/`-o` are dropped: a host that passed bytes has no
/// path for the engine to write a copy to, and expects the result instead.
RunResult runOnBytes(const std::string& command, const std::vector<std::string>& args,
                     const std::string& bytes, const std::string& name, const std::string& kind);

}  // namespace anyfile
