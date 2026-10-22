#include "markdown_handler.hpp"

#include <algorithm>
#include <cctype>
#include <regex>

#include "../core/util.hpp"

namespace anyfile {

namespace {
const char* BOLD = "\x1b[1m";
const char* DIM = "\x1b[2m";
const char* ITAL = "\x1b[3m";
const char* CYAN = "\x1b[36m";
const char* YELLOW = "\x1b[33m";
const char* GREEN = "\x1b[32m";
const char* RESET = "\x1b[0m";

std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t"), b = s.find_last_not_of(" \t\r");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}
}  // namespace

std::vector<Command> MarkdownHandler::commands() const {
    auto cs = TextHandler::commands();
    std::vector<Command> md = {
        {"render", "[--no-color]", "Pretty-print with ANSI styling for headings, lists, code"},
        {"outline", "", "List headings with their line numbers"},
        {"section", "<heading>", "Print one section (heading through the next heading of same or higher level)"},
        {"replace-section", "<heading> <text>", "Replace a section's body, keeping the heading line"},
        {"add-section", "<level> <heading> [text]", "Append a new heading (level 1-6) with optional body"},
        {"links", "", "List [text](url) links"},
        {"toc", "", "Generate a table of contents in Markdown"},
    };
    cs.insert(cs.begin(), md.begin(), md.end());
    return cs;
}

std::vector<MarkdownHandler::Heading> MarkdownHandler::headings() const {
    std::vector<Heading> hs;
    bool inFence = false;
    for (size_t i = 0; i < lines_.size(); ++i) {
        const std::string& l = lines_[i];
        std::string t = trim(l);
        if (t.rfind("```", 0) == 0 || t.rfind("~~~", 0) == 0) { inFence = !inFence; continue; }
        if (inFence) continue;
        if (!t.empty() && t[0] == '#') {
            int level = 0;
            while (level < static_cast<int>(t.size()) && t[static_cast<size_t>(level)] == '#') ++level;
            if (level <= 6 && (static_cast<size_t>(level) == t.size() || t[static_cast<size_t>(level)] == ' ')) {
                std::string text = trim(t.substr(static_cast<size_t>(level)));
                while (!text.empty() && text.back() == '#') text.pop_back();
                hs.push_back({i, level, trim(text)});
                continue;
            }
        }
        // Setext headings: a line followed by === or ---
        if (i + 1 < lines_.size() && !t.empty()) {
            std::string u = trim(lines_[i + 1]);
            if (u.size() >= 3 && (u.find_first_not_of('=') == std::string::npos || u.find_first_not_of('-') == std::string::npos)) {
                bool prevBlank = i == 0 || trim(lines_[i - 1]).empty();
                if (prevBlank && t[0] != '-' && t[0] != '*' && t[0] != '|') hs.push_back({i, u[0] == '=' ? 1 : 2, t});
            }
        }
    }
    return hs;
}

bool MarkdownHandler::sectionRange(const std::string& title, size_t& start, size_t& end, std::ostream& err) const {
    auto hs = headings();
    std::string want = lower(trim(title));
    for (size_t k = 0; k < hs.size(); ++k) {
        if (lower(hs[k].text) != want) continue;
        start = hs[k].line;
        end = lines_.size();
        for (size_t j = k + 1; j < hs.size(); ++j) if (hs[j].level <= hs[k].level) { end = hs[j].line; break; }
        return true;
    }
    err << "error: no heading \"" << title << "\"";
    if (!hs.empty()) { err << ". Available:"; for (const auto& h : hs) err << " \"" << h.text << "\""; }
    err << "\n";
    return false;
}

void MarkdownHandler::describe(std::ostream& out) {
    TextHandler::describe(out);
    auto saved = lines_;
    lines_ = util::splitLines(data_);
    auto hs = headings();
    lines_ = saved;
    out << "headings:   " << hs.size() << "\n";
    if (!hs.empty()) out << "title:      " << hs[0].text << "\n";
}

std::string MarkdownHandler::renderInline(const std::string& s, bool color) {
    if (!color) return s;
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '`') {
            size_t e = s.find('`', i + 1);
            if (e != std::string::npos) { out += std::string(YELLOW) + s.substr(i + 1, e - i - 1) + RESET; i = e; continue; }
        }
        if (s.compare(i, 2, "**") == 0 || s.compare(i, 2, "__") == 0) {
            size_t e = s.find(s.substr(i, 2), i + 2);
            if (e != std::string::npos) { out += std::string(BOLD) + renderInline(s.substr(i + 2, e - i - 2), color) + RESET; i = e + 1; continue; }
        }
        if ((s[i] == '*' || s[i] == '_') && i + 1 < s.size() && s[i + 1] != ' ') {
            size_t e = s.find(s[i], i + 1);
            if (e != std::string::npos && e > i + 1) { out += std::string(ITAL) + s.substr(i + 1, e - i - 1) + RESET; i = e; continue; }
        }
        if (s[i] == '[') {
            size_t m = s.find("](", i), e = m == std::string::npos ? m : s.find(')', m);
            if (e != std::string::npos) { out += std::string(CYAN) + s.substr(i + 1, m - i - 1) + RESET + DIM + " (" + s.substr(m + 2, e - m - 2) + ")" + RESET; i = e; continue; }
        }
        out += s[i];
    }
    return out;
}

Status MarkdownHandler::run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    static const std::vector<std::string> mine = {"render", "outline", "section", "replace-section", "add-section", "links", "toc"};
    if (std::find(mine.begin(), mine.end(), cmd) == mine.end()) return TextHandler::run(cmd, args, out, err);
    if (!loadLines(err)) return Status::Error;

    if (cmd == "render") {
        bool color = std::find(args.begin(), args.end(), "--no-color") == args.end();
        bool inFence = false;
        for (const auto& l : lines_) {
            std::string t = trim(l);
            if (t.rfind("```", 0) == 0 || t.rfind("~~~", 0) == 0) { inFence = !inFence; out << (color ? DIM : "") << l << (color ? RESET : "") << "\n"; continue; }
            if (inFence) { out << (color ? GREEN : "") << l << (color ? RESET : "") << "\n"; continue; }
            if (!t.empty() && t[0] == '#') {
                size_t lvl = 0; while (lvl < t.size() && t[lvl] == '#') ++lvl;
                std::string text = trim(t.substr(lvl));
                if (color) out << BOLD << (lvl == 1 ? CYAN : "") << std::string(lvl - 1, ' ') << text << RESET << "\n";
                else out << l << "\n";
                if (lvl == 1 && color) out << CYAN << std::string(std::min<size_t>(text.size(), 60), '=') << RESET << "\n";
                continue;
            }
            size_t indent = l.find_first_not_of(' ');
            std::string pad = indent == std::string::npos ? "" : l.substr(0, indent);
            if (t.rfind("- ", 0) == 0 || t.rfind("* ", 0) == 0 || t.rfind("+ ", 0) == 0) { out << pad << (color ? "• " : "- ") << renderInline(t.substr(2), color) << "\n"; continue; }
            if (t.rfind("> ", 0) == 0) { out << pad << (color ? DIM : "") << "│ " << renderInline(t.substr(2), color) << (color ? RESET : "") << "\n"; continue; }
            if (t == "---" || t == "***") { out << (color ? DIM : "") << std::string(40, '-') << (color ? RESET : "") << "\n"; continue; }
            out << pad << renderInline(t, color) << "\n";
        }
        return Status::Ok;
    }
    if (cmd == "outline") {
        for (const auto& h : headings()) out << (h.line + 1) << "\t" << std::string(static_cast<size_t>(h.level - 1) * 2, ' ') << h.text << "\n";
        return Status::Ok;
    }
    if (cmd == "toc") {
        for (const auto& h : headings()) {
            std::string anchor;
            for (unsigned char c : lower(h.text)) { if (std::isalnum(c)) anchor += static_cast<char>(c); else if (c == ' ' || c == '-') anchor += '-'; }
            out << std::string(static_cast<size_t>(h.level - 1) * 2, ' ') << "- [" << h.text << "](#" << anchor << ")\n";
        }
        return Status::Ok;
    }
    if (cmd == "links") {
        std::regex re(R"(\[([^\]]*)\]\(([^)\s]+)[^)]*\))");
        for (size_t i = 0; i < lines_.size(); ++i) {
            for (auto it = std::sregex_iterator(lines_[i].begin(), lines_[i].end(), re); it != std::sregex_iterator(); ++it)
                out << (i + 1) << "\t" << (*it)[1] << "\t" << (*it)[2] << "\n";
        }
        return Status::Ok;
    }
    if (cmd == "section") {
        if (args.empty()) { err << "usage: section <heading>\n"; return Status::BadUsage; }
        size_t s, e;
        if (!sectionRange(args[0], s, e, err)) return Status::Error;
        for (size_t i = s; i < e; ++i) out << lines_[i] << "\n";
        return Status::Ok;
    }
    if (cmd == "replace-section") {
        if (args.size() < 2) { err << "usage: replace-section <heading> <text>\n"; return Status::BadUsage; }
        size_t s, e;
        if (!sectionRange(args[0], s, e, err)) return Status::Error;
        auto body = util::splitLines(util::unescape(args[1]));
        std::vector<std::string> repl = {lines_[s], ""};
        repl.insert(repl.end(), body.begin(), body.end());
        if (e < lines_.size()) repl.push_back("");
        lines_.erase(lines_.begin() + static_cast<long>(s), lines_.begin() + static_cast<long>(e));
        lines_.insert(lines_.begin() + static_cast<long>(s), repl.begin(), repl.end());
        if (!storeLines(err)) return Status::Error;
        out << "replaced section \"" << args[0] << "\" (" << body.size() << " body lines)\n";
        return Status::Ok;
    }
    if (cmd == "add-section") {
        size_t level;
        if (args.size() < 2 || !util::parseSize(args[0], level) || level < 1 || level > 6) { err << "usage: add-section <level 1-6> <heading> [text]\n"; return Status::BadUsage; }
        if (!lines_.empty() && !trim(lines_.back()).empty()) lines_.push_back("");
        lines_.push_back(std::string(level, '#') + " " + args[1]);
        if (args.size() >= 3) {
            lines_.push_back("");
            for (const auto& l : util::splitLines(util::unescape(args[2]))) lines_.push_back(l);
        }
        trailingNewline_ = true;
        if (!storeLines(err)) return Status::Error;
        out << "added section \"" << args[1] << "\" at line " << (lines_.size() - (args.size() >= 3 ? util::splitLines(util::unescape(args[2])).size() + 1 : 0)) << "\n";
        return Status::Ok;
    }
    return Status::Unknown;
}

}  // namespace anyfile
