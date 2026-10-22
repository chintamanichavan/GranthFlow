#include "epub_handler.hpp"

#include <algorithm>
#include <cstdlib>

#include "../core/util.hpp"

namespace anyfile {

std::vector<Command> EpubHandler::commands() const {
    return {
        {"text", "[chapter]", "Print the whole book as plain text, or one chapter (1-based)"},
        {"chapters", "", "List chapters in reading order: number, title, file inside the archive"},
        {"meta", "", "Show book metadata (title, creator, language, ...)"},
        {"files", "", "List every file in the archive with its size"},
        {"cat", "<file>", "Print one file from the archive as stored, e.g. a chapter's XHTML"},
        {"cover", "", "Print the name of the cover image inside the archive (use cat to get its bytes)"},
        {"set-meta", "<key> <value> [--out file]", "Set a metadata entry, e.g. set-meta title \"My book\""},
        {"replace", "<old> <new> [--chapter n] [--all] [--out file]", "Replace literal text in chapter text (not across tags)"},
    };
}

bool EpubHandler::open(std::ostream& err) {
    if (book_) return true;
    if (!load(err)) return false;
    auto b = std::make_unique<epub::Book>();
    std::string e;
    if (!b->load(data_, e)) { err << "error: " << e << "\n"; return false; }
    book_ = std::move(b);
    return true;
}

bool EpubHandler::commit(const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    std::string target = path_;
    for (size_t i = 0; i + 1 < args.size(); ++i) if (args[i] == "--out" || args[i] == "-o") target = args[i + 1];
    std::string e;
    if (!util::writeFile(target, book_->serialize(), e)) { err << "error: " << e << "\n"; return false; }
    out << "saved " << target << "\n";
    return true;
}

void EpubHandler::describe(std::ostream& out) {
    std::ostream devnull(nullptr);
    if (!open(devnull)) { out << "epub:       unreadable\n"; return; }
    out << "epub:       version " << (book_->version().empty() ? "?" : book_->version()) << ", " << book_->chapters().size() << " chapters, "
        << book_->archive().entries().size() << " files"
        << (book_->archive().has("META-INF/encryption.xml") ? ", has encrypted or obfuscated parts" : "") << "\n";
    if (!book_->meta("title").empty()) out << "Title:      " << book_->meta("title") << "\n";
    if (!book_->meta("creator").empty()) out << "Author:     " << book_->meta("creator") << "\n";
    if (!book_->meta("language").empty()) out << "Language:   " << book_->meta("language") << "\n";
}

Status EpubHandler::run(const std::string& cmd, const std::vector<std::string>& argsIn, std::ostream& out, std::ostream& err) {
    static const std::vector<std::string> mine = {"text", "chapters", "meta", "files", "cat", "cover", "set-meta", "replace"};
    if (std::find(mine.begin(), mine.end(), cmd) == mine.end()) return ByteHandler::run(cmd, argsIn, out, err);
    if (!open(err)) return Status::Error;
    epub::Book& book = *book_;

    bool all = false;
    size_t chapterFlag = 0;
    std::vector<std::string> args;
    for (size_t i = 0; i < argsIn.size(); ++i) {
        if (argsIn[i] == "--all") { all = true; continue; }
        if ((argsIn[i] == "--out" || argsIn[i] == "-o") && i + 1 < argsIn.size()) { ++i; continue; }
        if (argsIn[i] == "--chapter" && i + 1 < argsIn.size()) {
            if (!util::parseSize(argsIn[++i], chapterFlag) || chapterFlag == 0) { err << "error: bad chapter number\n"; return Status::BadUsage; }
            continue;
        }
        args.push_back(argsIn[i]);
    }

    if (cmd == "chapters") {
        for (size_t i = 0; i < book.chapters().size(); ++i) out << (i + 1) << "\t" << book.chapterTitle(i) << "\t" << book.chapters()[i].path << "\n";
        return Status::Ok;
    }
    if (cmd == "meta") {
        for (const auto& [key, value] : book.metadata()) out << key << ": " << value << "\n";
        return Status::Ok;
    }
    if (cmd == "cover") {
        if (book.coverPath().empty()) { err << "error: this book has no cover image\n"; return Status::Error; }
        out << book.coverPath() << "\n";
        return Status::Ok;
    }
    if (cmd == "files") {
        for (const auto& e : book.archive().entries()) out << e.size << "\t" << e.name << "\n";
        return Status::Ok;
    }
    if (cmd == "cat") {
        if (args.empty()) { err << "usage: cat <file>\n"; return Status::BadUsage; }
        std::string content, e;
        if (!book.archive().read(args[0], content, e)) { err << "error: " << e << "\n"; return Status::Error; }
        out << content;
        return Status::Ok;
    }
    if (cmd == "text") {
        size_t only = 0;
        if (!args.empty() && (!util::parseSize(args[0], only) || only == 0)) { err << "usage: text [chapter]\n"; return Status::BadUsage; }
        if (only) {
            std::string text, e;
            if (!book.chapterText(only - 1, text, e)) { err << "error: " << e << "\n"; return Status::Error; }
            out << text;
            return Status::Ok;
        }
        Status result = Status::Ok;
        for (size_t i = 0; i < book.chapters().size(); ++i) {
            std::string text, title, e;
            // One unreadable chapter should not hide the rest of the book.
            if (!book.chapterText(i, text, e, &title)) {
                out << "== " << (i + 1) << ". " << book.chapterTitle(i) << " ==\n\n";
                err << "error: " << e << "\n";
                result = Status::Error;
                continue;
            }
            out << "== " << (i + 1) << ". " << title << " ==\n\n" << text << "\n";
        }
        return result;
    }
    if (cmd == "set-meta") {
        if (args.size() < 2) { err << "usage: set-meta <key> <value> [--out file]\n"; return Status::BadUsage; }
        std::string e;
        if (!book.setMeta(args[0], args[1], e)) { err << "error: " << e << "\n"; return Status::BadUsage; }
        out << "set " << args[0] << " = \"" << args[1] << "\"\n";
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    if (cmd == "replace") {
        if (args.size() < 2) { err << "usage: replace <old> <new> [--chapter n] [--all] [--out file]\n"; return Status::BadUsage; }
        if (chapterFlag > book.chapters().size()) { err << "error: no chapter " << chapterFlag << " (book has " << book.chapters().size() << ")\n"; return Status::Error; }
        std::string from = util::unescape(args[0]), to = util::unescape(args[1]);
        int total = 0;
        for (size_t i = 0; i < book.chapters().size(); ++i) {
            if (chapterFlag && chapterFlag != i + 1) continue;
            if (total > 0 && !all) break;
            std::string e;
            int n = book.replaceText(i, from, to, all, e);
            if (n < 0) { err << "error: " << e << "\n"; return Status::Error; }
            if (n) out << "chapter " << (i + 1) << ": " << n << " replacement" << (n == 1 ? "" : "s") << "\n";
            total += n;
        }
        if (total == 0) {
            err << "no match for \"" << args[0] << "\" in chapter text.\n"
                << "hint: text that crosses a tag (part of it bold or italic) or a line break in the source cannot be matched this way\n";
            return Status::Error;
        }
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    return Status::Unknown;
}

}  // namespace anyfile
