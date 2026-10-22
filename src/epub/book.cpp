#include "book.hpp"

#include <algorithm>
#include <cctype>
#include <set>

#include "xml.hpp"

namespace anyfile::epub {

namespace {
bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'; }

std::string collapse(const std::string& s) {
    std::string out;
    bool space = false;
    for (char c : s) {
        if (isSpace(c)) { space = true; continue; }
        if (space && !out.empty()) out += ' ';
        space = false;
        out += c;
    }
    return out;
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

std::string percentDecode(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size() && std::isxdigit(static_cast<unsigned char>(s[i + 1])) && std::isxdigit(static_cast<unsigned char>(s[i + 2]))) {
            out += static_cast<char>(std::stoi(s.substr(i + 1, 2), nullptr, 16));
            i += 2;
        } else {
            out += s[i];
        }
    }
    return out;
}

// The spec allows UTF-16 chapters; they are rare, and reading them as UTF-8 would print garbage.
bool isUtf16(const std::string& s) {
    return s.size() >= 2 && ((s[0] == '\xFF' && s[1] == '\xFE') || (s[0] == '\xFE' && s[1] == '\xFF'));
}

const std::set<std::string> kParagraph = {"p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "table", "ul", "ol", "dl",
                                          "hr", "figure", "section", "article", "header", "footer", "aside", "nav"};
const std::set<std::string> kLine = {"div", "li", "tr", "dt", "dd", "br", "figcaption", "caption"};
}  // namespace

std::string resolvePath(const std::string& base, const std::string& href) {
    std::string target = percentDecode(href.substr(0, href.find_first_of("#?")));
    std::vector<std::string> parts;
    auto push = [&](const std::string& path, bool dropLast) {
        size_t start = 0;
        std::vector<std::string> segs;
        while (start <= path.size()) {
            size_t slash = path.find('/', start);
            if (slash == std::string::npos) slash = path.size();
            segs.push_back(path.substr(start, slash - start));
            start = slash + 1;
        }
        if (dropLast && !segs.empty()) segs.pop_back();
        for (const auto& s : segs) {
            if (s.empty() || s == ".") continue;
            if (s == "..") { if (!parts.empty()) parts.pop_back(); continue; }
            parts.push_back(s);
        }
    };
    if (target.empty() || target[0] != '/') push(base, true);   // a leading slash means the archive root
    push(target, false);
    std::string out;
    for (const auto& p : parts) { if (!out.empty()) out += '/'; out += p; }
    return out;
}

std::string htmlToText(const std::string& xhtml, std::string* heading) {
    // A fragment without <body> is all content; otherwise only the body is text.
    bool inBody = xhtml.find("<body") == std::string::npos;
    int skip = 0, pre = 0;
    bool space = false, bullet = false, headingDone = false;
    std::string out, title, firstHeading;
    std::string* capture = nullptr;

    // Ensures the output ends with exactly n newlines (more are kept), unless nothing was written yet.
    auto breakTo = [&](size_t n) {
        if (bullet) return;   // "- " was just written; the item's text belongs on the same line
        while (!out.empty() && out.back() == ' ') out.pop_back();
        space = false;
        if (out.empty()) return;
        size_t have = 0;
        while (have < out.size() && out[out.size() - 1 - have] == '\n') ++have;
        if (have < n) out.append(n - have, '\n');
    };
    auto emit = [&](const std::string& s) {
        for (char c : s) {
            if (isSpace(c)) { space = true; continue; }
            if (space && !out.empty() && out.back() != '\n' && !bullet) out += ' ';
            space = bullet = false;
            out += c;
        }
    };

    xml::Reader reader(xhtml);
    xml::Token t;
    while (reader.next(t)) {
        if (t.kind == xml::Token::Text) {
            std::string s = t.cdata ? t.text : xml::decodeEntities(t.text);
            if (capture) *capture += s;
            if (!inBody || skip) continue;
            if (pre) { out += s; bullet = false; } else emit(s);
            continue;
        }
        std::string name = xml::localName(t.name);
        bool open = t.kind == xml::Token::Open;
        if (name == "body") { inBody = open; continue; }
        if (name == "script" || name == "style") {
            if (open && !t.selfClosing) ++skip; else if (!open && skip) --skip;
            continue;
        }
        if (!inBody) {
            if (name == "title") capture = open ? &title : nullptr;
            continue;
        }
        if (skip) continue;
        if ((name == "h1" || name == "h2" || name == "h3") && !headingDone) {
            if (open) capture = &firstHeading; else { capture = nullptr; headingDone = true; }
        }
        if (kParagraph.count(name)) breakTo(2);
        else if (kLine.count(name)) breakTo(1);
        if (name == "li" && open) { out += "- "; bullet = true; space = false; }
        if ((name == "td" || name == "th") && !open) space = true;
        if (name == "pre") pre = open ? pre + 1 : std::max(0, pre - 1);
        if (name == "img" && open && !t.attr("alt").empty()) emit("[" + t.attr("alt") + "]");
    }
    while (!out.empty() && (isSpace(out.back()))) out.pop_back();
    if (!out.empty()) out += '\n';
    if (heading) *heading = collapse(firstHeading.empty() ? title : firstHeading);
    return out;
}

bool Book::load(std::string bytes, std::string& error) {
    if (!zip_.load(std::move(bytes), error)) return false;
    std::string container;
    if (!zip_.read("META-INF/container.xml", container, error)) { error = "not an EPUB: " + error; return false; }
    opfPath_.clear();
    xml::Reader reader(container);
    xml::Token t;
    while (opfPath_.empty() && reader.next(t)) {
        if (t.kind == xml::Token::Open && xml::localName(t.name) == "rootfile") opfPath_ = t.attr("full-path");
    }
    if (opfPath_.empty()) { error = "not an EPUB: container.xml names no package file"; return false; }
    if (!zip_.read(opfPath_, opf_, error)) return false;
    parsePackage();
    return true;
}

void Book::parsePackage() {
    struct Item { std::string href, type, properties; };
    std::map<std::string, Item> manifest;
    std::vector<std::string> spine;
    std::string section, pendingKey, tocId, coverId;
    metadata_.clear();
    chapters_.clear();
    coverPath_.clear();

    xml::Reader reader(opf_);
    xml::Token t;
    while (reader.next(t)) {
        std::string name = t.kind == xml::Token::Text ? "" : xml::localName(t.name);
        if (t.kind == xml::Token::Text) {
            std::string value = collapse(t.cdata ? t.text : xml::decodeEntities(t.text));
            if (!pendingKey.empty() && !value.empty()) metadata_.emplace_back(pendingKey, value);
            pendingKey.clear();
        } else if (t.kind == xml::Token::Close) {
            if (name == section) section.clear();
            pendingKey.clear();
        } else if (name == "package") {
            version_ = t.attr("version");
        } else if (name == "metadata" || name == "manifest" || name == "spine") {
            section = name;
            if (name == "spine") tocId = t.attr("toc");
        } else if (section == "metadata" && lower(t.name).rfind("dc:", 0) == 0 && !t.selfClosing) {
            pendingKey = name;
        } else if (section == "metadata" && name == "meta" && t.attr("name") == "cover") {
            coverId = t.attr("content");                // EPUB 2: <meta name="cover" content="item-id"/>
        } else if (section == "manifest" && name == "item") {
            manifest[t.attr("id")] = {t.attr("href"), t.attr("media-type"), t.attr("properties")};
        } else if (section == "spine" && name == "itemref") {
            spine.push_back(t.attr("idref"));
        }
    }

    // The cover: EPUB 3 marks it with properties="cover-image", EPUB 2 names it in a <meta>, and
    // many older books only call it "cover" in the item's id or file name.
    auto isImage = [](const Item& item) { return item.type.rfind("image/", 0) == 0; };
    std::string cover;
    for (const auto& [id, item] : manifest) {
        if ((" " + item.properties + " ").find(" cover-image ") != std::string::npos) cover = item.href;
    }
    if (cover.empty() && manifest.count(coverId) && isImage(manifest[coverId])) cover = manifest[coverId].href;
    if (cover.empty()) {
        for (const auto& [id, item] : manifest) {
            if (isImage(item) && (lower(id).find("cover") != std::string::npos || lower(item.href).find("cover") != std::string::npos)) {
                cover = item.href;
                break;
            }
        }
    }
    if (!cover.empty() && zip_.has(resolvePath(opfPath_, cover))) coverPath_ = resolvePath(opfPath_, cover);

    // Chapter names come from the EPUB 3 navigation document when there is one, else the EPUB 2 NCX.
    std::map<std::string, std::string> labels;
    for (const auto& [id, item] : manifest) {
        if ((" " + item.properties + " ").find(" nav ") != std::string::npos) readLabels(resolvePath(opfPath_, item.href), false, labels);
    }
    if (labels.empty()) {
        for (const auto& [id, item] : manifest) {
            if (id == tocId || item.type == "application/x-dtbncx+xml") readLabels(resolvePath(opfPath_, item.href), true, labels);
        }
    }
    for (const auto& id : spine) {
        auto it = manifest.find(id);
        if (it == manifest.end()) continue;
        std::string path = resolvePath(opfPath_, it->second.href);
        auto label = labels.find(path);
        chapters_.push_back({path, label == labels.end() ? "" : label->second});
    }
}

void Book::readLabels(const std::string& path, bool ncx, std::map<std::string, std::string>& labels) const {
    std::string doc, ignored;
    if (!zip_.read(path, doc, ignored)) return;   // a missing contents file only costs the labels
    xml::Reader reader(doc);
    xml::Token t;
    std::string label, target;
    bool collecting = false;
    while (reader.next(t)) {
        std::string name = t.kind == xml::Token::Text ? "" : xml::localName(t.name);
        if (t.kind == xml::Token::Text) {
            if (collecting) label += t.cdata ? t.text : xml::decodeEntities(t.text);
        } else if (ncx) {
            // <navLabel><text>Name</text></navLabel><content src="file#frag"/>
            if (name == "text") { collecting = t.kind == xml::Token::Open; if (collecting) label.clear(); }
            else if (name == "content" && t.kind == xml::Token::Open) labels.emplace(resolvePath(path, t.attr("src")), collapse(label));
        } else if (name == "a") {
            // <a href="file#frag">Name</a>; the first link to a file names it.
            if (t.kind == xml::Token::Open) { collecting = true; label.clear(); target = resolvePath(path, t.attr("href")); }
            else if (collecting) { collecting = false; labels.emplace(target, collapse(label)); }
        }
    }
}

std::string Book::meta(const std::string& key) const {
    for (const auto& m : metadata_) if (m.first == key) return m.second;
    return "";
}

bool Book::readChapter(size_t index, std::string& xhtml, std::string& error) const {
    if (index >= chapters_.size()) { error = "no chapter " + std::to_string(index + 1) + " (book has " + std::to_string(chapters_.size()) + ")"; return false; }
    if (!zip_.read(chapters_[index].path, xhtml, error)) return false;
    if (isUtf16(xhtml)) { error = chapters_[index].path + " is UTF-16, which is not supported"; return false; }
    return true;
}

std::string Book::fileName(size_t index) const {
    const std::string& path = chapters_[index].path;
    size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

bool Book::chapterText(size_t index, std::string& out, std::string& error, std::string* title) const {
    std::string xhtml, heading;
    if (!readChapter(index, xhtml, error)) return false;
    out = htmlToText(xhtml, &heading);
    if (title) *title = !chapters_[index].label.empty() ? chapters_[index].label : !heading.empty() ? heading : fileName(index);
    return true;
}

std::string Book::chapterTitle(size_t index) const {
    if (index >= chapters_.size()) return "";
    if (!chapters_[index].label.empty()) return chapters_[index].label;
    std::string text, title, ignored;
    return chapterText(index, text, ignored, &title) ? title : fileName(index);
}

bool Book::setMeta(const std::string& rawKey, const std::string& value, std::string& error) {
    std::string key = lower(rawKey);
    if (key == "author") key = "creator";
    if (key.empty() || !std::all_of(key.begin(), key.end(), [](unsigned char c) { return std::isalpha(c); })) {
        error = "metadata key must be a word such as title, creator, language";
        return false;
    }
    xml::Reader reader(opf_);
    xml::Token t;
    size_t valueStart = std::string::npos, valueEnd = 0, metadataClose = std::string::npos;
    bool inMetadata = false;
    while (reader.next(t)) {
        if (t.kind == xml::Token::Text) continue;
        std::string name = xml::localName(t.name);
        if (name == "metadata") {
            inMetadata = t.kind == xml::Token::Open;
            if (!inMetadata) { metadataClose = t.begin; break; }
        } else if (inMetadata && name == key && lower(t.name).rfind("dc:", 0) == 0) {
            if (t.kind == xml::Token::Open && !t.selfClosing && valueStart == std::string::npos) valueStart = t.end;
            else if (t.kind == xml::Token::Close && valueStart != std::string::npos) { valueEnd = t.begin; break; }
        }
    }
    if (valueStart != std::string::npos && valueEnd >= valueStart) {
        opf_.replace(valueStart, valueEnd - valueStart, xml::escape(value));
    } else if (metadataClose != std::string::npos) {
        // Books declare the dc prefix on <metadata> or <package>; declare it here if this one does not.
        std::string ns = opf_.find("xmlns:dc=") == std::string::npos ? " xmlns:dc=\"http://purl.org/dc/elements/1.1/\"" : "";
        opf_.insert(metadataClose, "<dc:" + key + ns + ">" + xml::escape(value) + "</dc:" + key + ">\n  ");
    } else {
        error = "package file has no <metadata> section";
        return false;
    }
    zip_.put(opfPath_, opf_);
    parsePackage();
    return true;
}

int Book::replaceText(size_t index, const std::string& from, const std::string& to, bool all, std::string& error) {
    if (from.empty()) { error = "text to replace is empty"; return -1; }
    std::string xhtml;
    if (!readChapter(index, xhtml, error)) return -1;

    struct Edit { size_t begin, end; std::string text; };
    std::vector<Edit> edits;
    int count = 0, skip = 0;
    bool inBody = xhtml.find("<body") == std::string::npos;
    xml::Reader reader(xhtml);
    xml::Token t;
    while (reader.next(t) && (all || count == 0)) {
        if (t.kind != xml::Token::Text) {
            std::string name = xml::localName(t.name);
            bool open = t.kind == xml::Token::Open;
            if (name == "body") inBody = open;
            else if (name == "script" || name == "style") { if (open && !t.selfClosing) ++skip; else if (!open && skip) --skip; }
            continue;
        }
        if (!inBody || skip || t.cdata) continue;
        // Match against what the reader sees, so "it's" finds "it&#8217;s" typed with the real quote.
        std::string text = xml::decodeEntities(t.text);
        int here = 0;
        for (size_t at = text.find(from); at != std::string::npos; at = text.find(from, at + to.size())) {
            text.replace(at, from.size(), to);
            ++here;
            if (!all) break;
        }
        if (here) { edits.push_back({t.begin, t.end, xml::escape(text)}); count += here; }
    }
    if (count == 0) return 0;
    for (auto e = edits.rbegin(); e != edits.rend(); ++e) xhtml.replace(e->begin, e->end - e->begin, e->text);   // back to front keeps offsets valid
    zip_.put(chapters_[index].path, xhtml);
    return count;
}

}  // namespace anyfile::epub
