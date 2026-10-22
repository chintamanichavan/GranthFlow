// anyfile: read and modify PDF, EPUB, Markdown, text and binary files from the command line.
#include <iostream>
#include <string>
#include <vector>

#include "core/handler.hpp"
#include "core/util.hpp"

namespace {

void usage(std::ostream& out) {
    out << "anyfile - read and modify PDF, EPUB, Markdown, text and arbitrary binary files\n\n"
           "usage: anyfile [--as pdf|epub|markdown|text|binary] <file> [command] [args...]\n"
           "       anyfile <file> help        list commands for that file type\n"
           "       anyfile --version\n\n"
           "With no command, prints an `info` summary. The file type is detected from\n"
           "its magic bytes and extension; --as overrides detection.\n\n"
           "common commands (any file):\n";
    for (const auto& c : anyfile::commonCommands()) {
        std::string head = c.name + " " + c.usage;
        out << "  " << head << std::string(head.size() < 34 ? 34 - head.size() : 1, ' ') << c.help << "\n";
    }
    out << "\ntext/markdown:  show lines grep replace replace-regex append insert set-line delete\n"
           "markdown only:  render outline section replace-section add-section links toc\n"
           "pdf:            text pages meta object set-meta replace add-page add-note delete-page\n"
           "epub:           text chapters meta files cat set-meta replace\n\n"
           "Modifying commands write in place; PDF and EPUB commands accept --out <file> to write elsewhere.\n";
}

}  // namespace

int main(int argc, char** argv) {
    std::vector<std::string> argv_(argv + 1, argv + argc);
    std::string forced;
    std::vector<std::string> positional;
    for (size_t i = 0; i < argv_.size(); ++i) {
        const std::string& a = argv_[i];
        if (positional.empty() && (a == "-h" || a == "--help")) { usage(std::cout); return 0; }
        if (positional.empty() && a == "--version") { std::cout << "anyfile 0.1.0\n"; return 0; }
        if (positional.empty() && a == "--as" && i + 1 < argv_.size()) { forced = argv_[++i]; continue; }
        if (positional.empty() && a.rfind("--as=", 0) == 0) { forced = a.substr(5); continue; }
        positional.push_back(a);
    }
    if (positional.empty()) { usage(std::cerr); return 2; }

    std::string path = positional[0];
    std::string cmd = positional.size() > 1 ? positional[1] : "info";
    std::vector<std::string> args(positional.begin() + (positional.size() > 1 ? 2 : 1), positional.end());

    if (!anyfile::util::fileExists(path)) {
        std::cerr << "error: no such file: " << path << "\n";
        return 1;
    }
    std::string detected;
    auto handler = anyfile::makeHandler(path, forced, detected);
    if (!handler) { std::cerr << "error: unknown type \"" << forced << "\" (use pdf, epub, markdown, text or binary)\n"; return 2; }

    anyfile::Status st = handler->run(cmd, args, std::cout, std::cerr);
    if (st == anyfile::Status::Unknown) {
        std::cerr << "error: \"" << cmd << "\" is not a command for " << detected << " files. Try: anyfile " << path << " help\n";
        return 2;
    }
    return static_cast<int>(st);
}
