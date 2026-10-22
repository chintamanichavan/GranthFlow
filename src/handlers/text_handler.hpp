#pragma once
#include "../core/handler.hpp"

namespace anyfile {

// Line-oriented reading and editing for plain text. Markdown builds on this.
class TextHandler : public ByteHandler {
public:
    explicit TextHandler(std::string path) : ByteHandler(std::move(path)) {}
    std::string kind() const override { return "text"; }
    std::vector<Command> commands() const override;
    Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) override;

protected:
    bool loadLines(std::ostream& err);
    bool storeLines(std::ostream& err);
    void describe(std::ostream& out) override;
    std::vector<std::string> lines_;
    std::string newline_ = "\n";
    bool trailingNewline_ = true;
};

}  // namespace anyfile
