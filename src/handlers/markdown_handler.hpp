#pragma once
#include "text_handler.hpp"

namespace anyfile {

// Markdown: everything TextHandler does, plus structure-aware commands.
class MarkdownHandler : public TextHandler {
public:
    explicit MarkdownHandler(std::string path) : TextHandler(std::move(path)) {}
    std::string kind() const override { return "markdown"; }
    std::vector<Command> commands() const override;
    Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) override;

private:
    struct Heading { size_t line; int level; std::string text; };
    std::vector<Heading> headings() const;
    bool sectionRange(const std::string& title, size_t& start, size_t& end, std::ostream& err) const;  // 0-based [start,end)
    void describe(std::ostream& out) override;
    static std::string renderInline(const std::string& s, bool color);
};

}  // namespace anyfile
