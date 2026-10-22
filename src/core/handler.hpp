// The plug-in interface every file type implements, plus the shared base with byte-level commands.
#pragma once
#include <memory>
#include <ostream>
#include <string>
#include <vector>

namespace anyfile {

struct Command {
    std::string name;
    std::string usage;   // arguments after the file path
    std::string help;
};

enum class Status { Ok = 0, Error = 1, BadUsage = 2, Unknown = 3 };

class FileHandler {
public:
    virtual ~FileHandler() = default;
    virtual std::string kind() const = 0;                       // "pdf", "markdown", "text", "binary"
    virtual std::vector<Command> commands() const = 0;          // commands this handler adds
    virtual Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) = 0;
    const std::string& path() const { return path_; }

protected:
    explicit FileHandler(std::string path) : path_(std::move(path)) {}
    std::string path_;
};

// Commands that make sense for any file: info, hex, patch, strings, truncate, copy-range.
class ByteHandler : public FileHandler {
public:
    explicit ByteHandler(std::string path) : FileHandler(std::move(path)) {}
    std::string kind() const override { return "binary"; }
    std::vector<Command> commands() const override;
    Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) override;

protected:
    bool load(std::ostream& err);
    bool store(std::ostream& err);
    virtual void describe(std::ostream& out);   // extra lines for `info`
    std::string data_;
    bool loaded_ = false;
};

std::unique_ptr<FileHandler> makeHandler(const std::string& path, const std::string& forcedKind, std::string& detected);
std::vector<Command> commonCommands();

}  // namespace anyfile
