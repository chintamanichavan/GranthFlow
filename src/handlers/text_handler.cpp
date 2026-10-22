#include "text_handler.hpp"

#include <algorithm>
#include <regex>

#include "../core/util.hpp"

namespace anyfile {

std::vector<Command> TextHandler::commands() const {
    return {
        {"show", "[start[:end]]", "Print the file, or a line range (1-based, inclusive)"},
        {"lines", "[start[:end]]", "Print with line numbers"},
        {"grep", "<regex>", "Print matching lines with numbers"},
        {"count", "", "Line, word and byte counts"},
        {"replace", "<old> <new> [--all]", "Replace the first (or every) occurrence of text"},
        {"replace-regex", "<regex> <replacement> [--all]", "Regex replace per line (ECMAScript syntax, $1 groups)"},
        {"append", "<text>", "Add a line at the end (\\n and \\t escapes allowed)"},
        {"insert", "<line> <text>", "Insert text before the given line number"},
        {"set-line", "<line> <text>", "Replace one line"},
        {"delete", "<start[:end]>", "Delete a line or line range"},
    };
}

bool TextHandler::loadLines(std::ostream& err) {
    if (!load(err)) return false;
    lines_ = util::splitLines(data_, &newline_);
    trailingNewline_ = data_.empty() || data_.back() == '\n';
    return true;
}

bool TextHandler::storeLines(std::ostream& err) {
    data_ = util::joinLines(lines_, newline_, trailingNewline_);
    return store(err);
}

void TextHandler::describe(std::ostream& out) {
    auto lines = util::splitLines(data_);
    size_t words = 0;
    for (const auto& l : lines) {
        bool in = false;
        for (unsigned char c : l) { bool sp = c == ' ' || c == '\t'; if (!sp && !in) ++words; in = !sp; }
    }
    out << "lines:      " << lines.size() << "\n";
    out << "words:      " << words << "\n";
    out << "newline:    " << (data_.find("\r\n") != std::string::npos ? "CRLF" : "LF") << "\n";
}

// Parses "5", "5:9", "5:" or ":9" into a 1-based inclusive range. Returns false on bad input.
static bool parseRange(const std::string& s, size_t total, size_t& start, size_t& end) {
    start = 1; end = total;
    if (s.empty()) return true;
    size_t colon = s.find(':');
    std::string a = colon == std::string::npos ? s : s.substr(0, colon);
    std::string b = colon == std::string::npos ? s : s.substr(colon + 1);
    if (!a.empty() && !util::parseSize(a, start)) return false;
    if (!b.empty() && !util::parseSize(b, end)) return false;
    if (start < 1) start = 1;
    if (end > total) end = total;
    return start <= end || total == 0;
}

Status TextHandler::run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    static const std::vector<std::string> mine = {"show", "lines", "grep", "count", "replace", "replace-regex", "append", "insert", "set-line", "delete"};
    if (std::find(mine.begin(), mine.end(), cmd) == mine.end()) return ByteHandler::run(cmd, args, out, err);
    if (!loadLines(err)) return Status::Error;

    bool all = std::find(args.begin(), args.end(), "--all") != args.end();
    std::vector<std::string> a;
    for (const auto& x : args) if (x != "--all") a.push_back(x);

    if (cmd == "show" || cmd == "lines") {
        size_t s, e;
        if (!parseRange(a.empty() ? "" : a[0], lines_.size(), s, e)) { err << "error: bad range\n"; return Status::BadUsage; }
        for (size_t i = s; i <= e && i <= lines_.size(); ++i) {
            if (cmd == "lines") out << i << "\t";
            out << lines_[i - 1] << "\n";
        }
        return Status::Ok;
    }
    if (cmd == "count") {
        describe(out);
        out << "bytes:      " << data_.size() << "\n";
        return Status::Ok;
    }
    if (cmd == "grep") {
        if (a.empty()) { err << "usage: grep <regex>\n"; return Status::BadUsage; }
        try {
            std::regex re(a[0]);
            for (size_t i = 0; i < lines_.size(); ++i) if (std::regex_search(lines_[i], re)) out << (i + 1) << ":" << lines_[i] << "\n";
        } catch (const std::regex_error& ex) { err << "error: bad regex: " << ex.what() << "\n"; return Status::BadUsage; }
        return Status::Ok;
    }
    if (cmd == "replace") {
        if (a.size() < 2) { err << "usage: replace <old> <new> [--all]\n"; return Status::BadUsage; }
        std::string from = util::unescape(a[0]), to = util::unescape(a[1]);
        if (from.empty()) { err << "error: search text is empty\n"; return Status::BadUsage; }
        size_t count = 0, pos = 0;
        while ((pos = data_.find(from, pos)) != std::string::npos) {
            data_.replace(pos, from.size(), to);
            pos += to.size();
            ++count;
            if (!all) break;
        }
        if (count == 0) { err << "no match for \"" << a[0] << "\"\n"; return Status::Error; }
        if (!store(err)) return Status::Error;
        out << "replaced " << count << " occurrence" << (count == 1 ? "" : "s") << "\n";
        return Status::Ok;
    }
    if (cmd == "replace-regex") {
        if (a.size() < 2) { err << "usage: replace-regex <regex> <replacement> [--all]\n"; return Status::BadUsage; }
        try {
            std::regex re(a[0]);
            size_t count = 0;
            auto flags = all ? std::regex_constants::format_default : std::regex_constants::format_first_only;
            for (auto& line : lines_) {
                if (!std::regex_search(line, re)) continue;
                line = std::regex_replace(line, re, a[1], flags);
                ++count;
                if (!all) break;
            }
            if (count == 0) { err << "no match\n"; return Status::Error; }
            if (!storeLines(err)) return Status::Error;
            out << "changed " << count << " line" << (count == 1 ? "" : "s") << "\n";
        } catch (const std::regex_error& ex) { err << "error: bad regex: " << ex.what() << "\n"; return Status::BadUsage; }
        return Status::Ok;
    }
    if (cmd == "append") {
        if (a.empty()) { err << "usage: append <text>\n"; return Status::BadUsage; }
        for (const auto& l : util::splitLines(util::unescape(a[0]))) lines_.push_back(l);
        trailingNewline_ = true;
        if (!storeLines(err)) return Status::Error;
        out << "appended; file now has " << lines_.size() << " lines\n";
        return Status::Ok;
    }
    if (cmd == "insert" || cmd == "set-line") {
        size_t n;
        if (a.size() < 2 || !util::parseSize(a[0], n) || n < 1) { err << "usage: " << cmd << " <line> <text>\n"; return Status::BadUsage; }
        auto newLines = util::splitLines(util::unescape(a[1]));
        if (newLines.empty()) newLines.push_back("");
        if (cmd == "insert") {
            if (n > lines_.size() + 1) { err << "error: line " << n << " is beyond end (" << lines_.size() << " lines)\n"; return Status::Error; }
            lines_.insert(lines_.begin() + static_cast<long>(n - 1), newLines.begin(), newLines.end());
        } else {
            if (n > lines_.size()) { err << "error: no line " << n << "\n"; return Status::Error; }
            lines_.erase(lines_.begin() + static_cast<long>(n - 1));
            lines_.insert(lines_.begin() + static_cast<long>(n - 1), newLines.begin(), newLines.end());
        }
        if (!storeLines(err)) return Status::Error;
        out << (cmd == "insert" ? "inserted" : "set") << " at line " << n << "\n";
        return Status::Ok;
    }
    if (cmd == "delete") {
        size_t s, e;
        if (a.empty() || !parseRange(a[0], lines_.size(), s, e) || s > lines_.size()) { err << "usage: delete <start[:end]>\n"; return Status::BadUsage; }
        lines_.erase(lines_.begin() + static_cast<long>(s - 1), lines_.begin() + static_cast<long>(e));
        if (!storeLines(err)) return Status::Error;
        out << "deleted lines " << s << "-" << e << "\n";
        return Status::Ok;
    }
    return Status::Unknown;
}

}  // namespace anyfile
