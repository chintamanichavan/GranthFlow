#include "pdf_handler.hpp"

#include <algorithm>
#include <ctime>

#include "../core/util.hpp"
#include "../pdf/filters.hpp"
#include "../pdf/text.hpp"

namespace anyfile {

using pdf::ObjPtr;

std::vector<Command> PdfHandler::commands() const {
    return {
        {"text", "[page] [--out file]", "Extract text from all pages or one page (1-based)"},
        {"pages", "", "List pages with their sizes and object numbers"},
        {"meta", "", "Show document information (Title, Author, ...)"},
        {"object", "<num>", "Dump one object by number (decoded stream shown for content streams)"},
        {"set-meta", "<Key> <value> [--out file]", "Set an Info entry, e.g. set-meta Title \"My doc\""},
        {"replace", "<old> <new> [--page n] [--all] [--out file]", "Replace literal text in page content (simple fonts only)"},
        {"add-page", "<text> [--out file]", "Append a page containing the given text (Helvetica, 12pt)"},
        {"add-note", "<page> <text> [--out file]", "Add a sticky-note annotation to a page"},
        {"delete-page", "<page> [--out file]", "Remove a page from the page tree"},
    };
}

bool PdfHandler::open(std::ostream& err) {
    if (doc_) return true;
    auto d = std::make_unique<pdf::Document>();
    std::string e;
    if (!d->load(path_, e)) { err << "error: " << e << "\n"; return false; }
    doc_ = std::move(d);
    return true;
}

std::string PdfHandler::outputPath(const std::vector<std::string>& args) const {
    for (size_t i = 0; i + 1 < args.size(); ++i) if (args[i] == "--out" || args[i] == "-o") return args[i + 1];
    return path_;
}

bool PdfHandler::commit(const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    std::string target = outputPath(args);
    std::string e;
    if (target == path_) {
        // Save through a temp file so an interrupted write never corrupts the original.
        std::string tmp = path_ + ".anyfile.tmp";
        if (!doc_->save(tmp, e)) { err << "error: " << e << "\n"; std::remove(tmp.c_str()); return false; }
        if (std::rename(tmp.c_str(), path_.c_str()) != 0) { err << "error: cannot replace " << path_ << "\n"; std::remove(tmp.c_str()); return false; }
    } else if (!doc_->save(target, e)) {
        err << "error: " << e << "\n";
        return false;
    }
    out << "saved " << target << " (incremental update appended)\n";
    return true;
}

void PdfHandler::describe(std::ostream& out) {
    std::ostream devnull(nullptr);
    if (!open(devnull)) { out << "pdf:        unreadable\n"; return; }
    out << "pdf:        version " << doc_->version() << ", " << doc_->pages().size() << " pages, "
        << doc_->objectCount() << " objects, " << (doc_->usesXrefStream() ? "xref stream" : "xref table")
        << (doc_->isEncrypted() ? ", ENCRYPTED" : "") << "\n";
    ObjPtr info = doc_->info();
    for (const char* k : {"Title", "Author", "Producer", "Creator"}) {
        ObjPtr v = doc_->resolve(info->get(k));
        if (v->isString()) out << k << ":" << std::string(11 - std::string(k).size(), ' ') << v->str << "\n";
    }
}

static std::string pdfDate() {
    char buf[32];
    std::time_t t = std::time(nullptr);
    std::strftime(buf, sizeof buf, "D:%Y%m%d%H%M%S", std::localtime(&t));
    return buf;
}

static void stripFlags(std::vector<std::string>& args, bool& all, int& page) {
    std::vector<std::string> clean;
    for (size_t i = 0; i < args.size(); ++i) {
        if (args[i] == "--all") { all = true; continue; }
        if ((args[i] == "--out" || args[i] == "-o") && i + 1 < args.size()) { ++i; continue; }
        if (args[i] == "--page" && i + 1 < args.size()) { page = std::atoi(args[++i].c_str()); continue; }
        clean.push_back(args[i]);
    }
    args = clean;
}

Status PdfHandler::run(const std::string& cmd, const std::vector<std::string>& argsIn, std::ostream& out, std::ostream& err) {
    static const std::vector<std::string> mine = {"text", "pages", "meta", "object", "set-meta", "replace", "add-page", "add-note", "delete-page"};
    if (std::find(mine.begin(), mine.end(), cmd) == mine.end()) return ByteHandler::run(cmd, argsIn, out, err);
    if (!open(err)) return Status::Error;
    pdf::Document& doc = *doc_;

    bool all = false;
    int pageFlag = 0;
    std::vector<std::string> args = argsIn;
    stripFlags(args, all, pageFlag);

    if (cmd == "pages") {
        auto pages = doc.pages();
        for (size_t i = 0; i < pages.size(); ++i) {
            ObjPtr mb = pages[i].mediaBox;
            out << (i + 1) << "\tobj " << pages[i].ref.num;
            if (mb->isArray() && mb->array.size() == 4)
                out << "\t" << doc.resolve(mb->array[2])->numValue() - doc.resolve(mb->array[0])->numValue() << " x "
                    << doc.resolve(mb->array[3])->numValue() - doc.resolve(mb->array[1])->numValue() << " pt";
            ObjPtr rot = doc.resolve(pages[i].dict->get("Rotate"));
            if (rot->isNumber() && rot->number != 0) out << "\trotate " << rot->intValue();
            out << "\n";
        }
        return Status::Ok;
    }
    if (cmd == "meta") {
        ObjPtr info = doc.info();
        if (!info->isDict() || info->dict.empty()) { out << "(no Info dictionary)\n"; return Status::Ok; }
        for (const auto& [k, v] : info->dict) {
            ObjPtr r = doc.resolve(v);
            out << k << ": " << (r->isString() ? r->str : pdf::serialize(r)) << "\n";
        }
        return Status::Ok;
    }
    if (cmd == "object") {
        size_t n;
        if (args.empty() || !util::parseSize(args[0], n)) { err << "usage: object <num>\n"; return Status::BadUsage; }
        ObjPtr o = doc.object(static_cast<int>(n));
        out << n << " 0 obj\n" << pdf::describe(o) << "\n";
        if (o->isStream()) {
            bool complete = true;
            std::string data = doc.streamData(o, &complete);
            if (!complete) out << "[stream uses an unsupported filter; raw length " << o->raw.size() << "]\n";
            else if (util::looksLikeText(data)) out << "--- decoded stream (" << data.size() << " bytes) ---\n" << data << "\n";
            else out << "--- decoded stream: " << data.size() << " bytes of binary data ---\n" << util::hexDump(data, 0, 0, 128);
        }
        return Status::Ok;
    }
    if (cmd == "text") {
        if (doc.isEncrypted()) err << "warning: document is encrypted; text will not be readable\n";
        auto pages = doc.pages();
        int only = pageFlag;
        if (!args.empty()) only = std::atoi(args[0].c_str());
        if (only < 0 || static_cast<size_t>(only) > pages.size()) { err << "error: page out of range (1-" << pages.size() << ")\n"; return Status::Error; }
        pdf::ExtractStats stats;
        std::string result;
        for (size_t i = 0; i < pages.size(); ++i) {
            if (only && static_cast<size_t>(only) != i + 1) continue;
            if (!only && pages.size() > 1) result += "===== page " + std::to_string(i + 1) + " =====\n";
            result += pdf::extractPageText(doc, pages[i], &stats);
        }
        std::string target = outputPath(argsIn);
        if (target != path_) {
            std::string e;
            if (!util::writeFile(target, result, e)) { err << "error: " << e << "\n"; return Status::Error; }
            out << "wrote " << result.size() << " bytes to " << target << "\n";
        } else {
            out << result;
        }
        if (stats.unmappedGlyphs) err << "note: " << stats.unmappedGlyphs << " glyphs had no Unicode mapping and were skipped\n";
        if (stats.unsupportedStreams) err << "note: " << stats.unsupportedStreams << " content streams used unsupported filters\n";
        return Status::Ok;
    }

    // ---- modifying commands ----
    if (doc.isEncrypted()) { err << "error: encrypted PDFs cannot be modified\n"; return Status::Error; }

    if (cmd == "set-meta") {
        if (args.size() < 2) { err << "usage: set-meta <Key> <value> [--out file]\n"; return Status::BadUsage; }
        ObjPtr old = doc.info();
        std::map<std::string, ObjPtr> d;
        if (old->isDict()) for (const auto& [k, v] : old->dict) d[k] = doc.resolve(v);
        d[args[0]] = pdf::makeString(util::unescape(args[1]));
        d["ModDate"] = pdf::makeString(pdfDate());
        auto ref = doc.infoRef();
        int num = ref ? ref->num : doc.allocateObject();
        doc.setObject(num, ref ? ref->gen : 0, pdf::makeDict(d));
        doc.setTrailerInfo({num, ref ? ref->gen : 0});
        out << "set /" << args[0] << " = \"" << args[1] << "\"\n";
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    if (cmd == "replace") {
        if (args.size() < 2) { err << "usage: replace <old> <new> [--page n] [--all] [--out file]\n"; return Status::BadUsage; }
        auto pages = doc.pages();
        int total = 0;
        for (size_t i = 0; i < pages.size(); ++i) {
            if (pageFlag && static_cast<size_t>(pageFlag) != i + 1) continue;
            if (total > 0 && !all) break;
            int n = pdf::replaceTextOnPage(doc, pages[i], util::unescape(args[0]), util::unescape(args[1]), all);
            if (n) out << "page " << (i + 1) << ": " << n << " replacement" << (n == 1 ? "" : "s") << "\n";
            total += n;
        }
        if (total == 0) {
            err << "no literal match for \"" << args[0] << "\" in page content.\n"
                << "hint: text split across several show operators, or set in a CID/subset font, cannot be matched this way\n";
            return Status::Error;
        }
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    if (cmd == "add-page") {
        if (args.empty()) { err << "usage: add-page <text> [--out file]\n"; return Status::BadUsage; }
        ObjPtr cat = doc.catalog();
        ObjPtr pagesRefObj = cat->get("Pages");
        ObjPtr pagesNode = doc.resolve(pagesRefObj);
        if (!pagesRefObj->isRef() || !pagesNode->isDict()) { err << "error: page tree root is not an indirect object; cannot append\n"; return Status::Error; }

        // Page size: copy the first page's MediaBox or default to US Letter.
        auto existing = doc.pages();
        ObjPtr mediaBox = pdf::makeArray({pdf::makeInt(0), pdf::makeInt(0), pdf::makeInt(612), pdf::makeInt(792)});
        if (!existing.empty() && existing.front().mediaBox->isArray()) mediaBox = existing.front().mediaBox;
        double top = 792;
        if (mediaBox->isArray() && mediaBox->array.size() == 4) top = doc.resolve(mediaBox->array[3])->numValue(792);

        std::string content = "BT\n/F1 12 Tf\n14 TL\n50 " + std::to_string(static_cast<int>(top - 60)) + " Td\n";
        for (const auto& line : util::splitLines(util::unescape(args[0]))) content += pdf::serialize(pdf::makeString(line)) + " Tj T*\n";
        content += "ET\n";

        int fontNum = doc.allocateObject();
        doc.setObject(fontNum, 0, pdf::makeDict({{"Type", pdf::makeName("Font")}, {"Subtype", pdf::makeName("Type1")},
                                                 {"BaseFont", pdf::makeName("Helvetica")}, {"Encoding", pdf::makeName("WinAnsiEncoding")}}));
        int contentNum = doc.allocateObject();
        doc.setObject(contentNum, 0, pdf::makeStream({{"Filter", pdf::makeName("FlateDecode")}}, pdf::flateEncode(content)));
        int pageNum = doc.allocateObject();
        doc.setObject(pageNum, 0, pdf::makeDict({{"Type", pdf::makeName("Page")}, {"Parent", pagesRefObj}, {"MediaBox", mediaBox},
                                                 {"Contents", pdf::makeRef(contentNum, 0)},
                                                 {"Resources", pdf::makeDict({{"Font", pdf::makeDict({{"F1", pdf::makeRef(fontNum, 0)}})}})}}));

        // New version of the root Pages node with one more kid.
        std::map<std::string, ObjPtr> pd = pagesNode->dict;
        ObjPtr kids = pdf::makeArray(doc.resolve(pagesNode->get("Kids"))->array);
        kids->array.push_back(pdf::makeRef(pageNum, 0));
        pd["Kids"] = kids;
        pd["Count"] = pdf::makeInt(doc.resolve(pagesNode->get("Count"))->intValue(static_cast<int>(existing.size())) + 1);
        doc.setObject(pagesRefObj->ref.num, pagesRefObj->ref.gen, pdf::makeDict(pd));
        out << "added page " << (existing.size() + 1) << " (object " << pageNum << ")\n";
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    if (cmd == "add-note") {
        if (args.size() < 2) { err << "usage: add-note <page> <text> [--out file]\n"; return Status::BadUsage; }
        auto pages = doc.pages();
        int p = std::atoi(args[0].c_str());
        if (p < 1 || static_cast<size_t>(p) > pages.size()) { err << "error: page out of range\n"; return Status::Error; }
        const pdf::PageInfo& page = pages[static_cast<size_t>(p - 1)];
        if (page.ref.num == 0) { err << "error: page is not an indirect object\n"; return Status::Error; }
        double top = 792;
        if (page.mediaBox->isArray() && page.mediaBox->array.size() == 4) top = doc.resolve(page.mediaBox->array[3])->numValue(792);
        int annotNum = doc.allocateObject();
        doc.setObject(annotNum, 0, pdf::makeDict({{"Type", pdf::makeName("Annot")}, {"Subtype", pdf::makeName("Text")},
                                                  {"Rect", pdf::makeArray({pdf::makeInt(40), pdf::makeNumber(top - 60, false), pdf::makeInt(60), pdf::makeNumber(top - 40, false)})},
                                                  {"Contents", pdf::makeString(util::unescape(args[1]))}, {"Name", pdf::makeName("Note")},
                                                  {"Open", pdf::makeBool(false)}, {"F", pdf::makeInt(4)}, {"C", pdf::makeArray({pdf::makeInt(1), pdf::makeNumber(0.9, false), pdf::makeInt(0)})},
                                                  {"M", pdf::makeString(pdfDate())}}));
        std::map<std::string, ObjPtr> pd = page.dict->dict;
        ObjPtr annots = pdf::makeArray(doc.resolve(page.dict->get("Annots"))->array);
        annots->array.push_back(pdf::makeRef(annotNum, 0));
        pd["Annots"] = annots;
        doc.setObject(page.ref.num, page.ref.gen, pdf::makeDict(pd));
        out << "added note annotation to page " << p << "\n";
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    if (cmd == "delete-page") {
        if (args.empty()) { err << "usage: delete-page <page> [--out file]\n"; return Status::BadUsage; }
        auto pages = doc.pages();
        int p = std::atoi(args[0].c_str());
        if (p < 1 || static_cast<size_t>(p) > pages.size()) { err << "error: page out of range\n"; return Status::Error; }
        if (pages.size() == 1) { err << "error: cannot delete the only page\n"; return Status::Error; }
        const pdf::PageInfo& page = pages[static_cast<size_t>(p - 1)];
        if (page.ref.num == 0 || page.parent.num == 0) { err << "error: page or parent is not an indirect object\n"; return Status::Error; }
        // Remove from parent's Kids and decrement Count up the chain.
        pdf::Ref parentRef = page.parent;
        ObjPtr parent = doc.object(parentRef.num);
        std::map<std::string, ObjPtr> pd = parent->dict;
        ObjPtr kids = pdf::makeArray();
        for (const auto& k : doc.resolve(parent->get("Kids"))->array) if (!(k->isRef() && k->ref == page.ref)) kids->array.push_back(k);
        pd["Kids"] = kids;
        pd["Count"] = pdf::makeInt(doc.resolve(parent->get("Count"))->intValue(1) - 1);
        doc.setObject(parentRef.num, parentRef.gen, pdf::makeDict(pd));
        ObjPtr up = parent->get("Parent");
        for (int guard = 0; up->isRef() && guard < 64; ++guard) {
            ObjPtr node = doc.object(up->ref.num);
            std::map<std::string, ObjPtr> nd = node->dict;
            nd["Count"] = pdf::makeInt(doc.resolve(node->get("Count"))->intValue(1) - 1);
            doc.setObject(up->ref.num, up->ref.gen, pdf::makeDict(nd));
            up = node->get("Parent");
        }
        out << "deleted page " << p << "\n";
        return commit(argsIn, out, err) ? Status::Ok : Status::Error;
    }
    return Status::Unknown;
}

}  // namespace anyfile
