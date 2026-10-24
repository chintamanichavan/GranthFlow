#include "engine.hpp"

#include <filesystem>
#include <random>
#include <sstream>

#include "util.hpp"

namespace anyfile {
namespace {

/// Bytes staged as a file the handlers can open. The name keeps the original extension, because
/// detection looks at it, and the directory is removed when the copy goes out of scope.
class StagedFile {
public:
    StagedFile(const std::string& bytes, const std::string& name) {
        static std::mt19937_64 rng{std::random_device{}()};
        std::error_code ec;
        dir_ = std::filesystem::temp_directory_path(ec) / ("anyfile-" + std::to_string(rng()));
        std::filesystem::create_directories(dir_, ec);
        path_ = (dir_ / ("file" + util::lowerExt(name))).string();
        std::string error;
        ok_ = util::writeFile(path_, bytes, error);
    }

    ~StagedFile() {
        std::error_code ec;
        std::filesystem::remove_all(dir_, ec);
    }

    StagedFile(const StagedFile&) = delete;
    StagedFile& operator=(const StagedFile&) = delete;

    bool ok() const { return ok_; }
    const std::string& path() const { return path_; }

    /// The staged bytes as they are now, after a command may have rewritten them.
    std::string contents() const {
        std::string data, error;
        return util::readFile(path_, data, error) ? data : std::string();
    }

private:
    std::filesystem::path dir_;
    std::string path_;
    bool ok_ = false;
};

}  // namespace

std::string detectKind(const std::string& bytes, const std::string& name) {
    StagedFile staged(bytes, name);
    std::string kind;
    makeHandler(staged.path(), "", kind);
    return kind;
}

std::vector<Command> commandsForKind(const std::string& kind) {
    std::string detected;
    auto handler = makeHandler("/nonexistent", kind, detected);   // a forced kind never touches the path
    if (!handler) return {};   // a kind runOnBytes would refuse offers no commands either
    std::vector<Command> out = handler->commands();
    const auto common = commonCommands();
    out.insert(out.end(), common.begin(), common.end());
    return out;
}

RunResult runOnBytes(const std::string& command, const std::vector<std::string>& args,
                     const std::string& bytes, const std::string& name, const std::string& kind) {
    RunResult result;
    StagedFile staged(bytes, name);
    if (!staged.ok()) {
        result.status = Status::Error;
        result.error = "could not stage the file's contents";
        return result;
    }

    std::vector<std::string> argv;
    argv.reserve(args.size());
    for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "--out" || args[i] == "-o") { ++i; continue; }   // its argument goes with it
        argv.push_back(args[i]);
    }

    std::string detected;
    auto handler = makeHandler(staged.path(), kind, detected);
    if (!handler) {
        result.status = Status::BadUsage;
        result.error = "unknown file kind";
        return result;
    }

    std::ostringstream out, err;
    result.status = handler->run(command, argv, out, err);
    if (result.status == Status::Unknown) {
        err << "\"" << command << "\" is not a command for " << detected << " files";
    }
    result.output = out.str();
    result.error = err.str();

    const std::string after = staged.contents();
    if (after != bytes) {
        result.changed = after;
        result.didChange = true;
    }
    return result;
}

}  // namespace anyfile
