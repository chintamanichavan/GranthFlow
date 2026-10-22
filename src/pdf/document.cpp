#include "document.hpp"

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <sstream>

#include "filters.hpp"
#include "parser.hpp"

namespace anyfile::pdf {

static ObjPtr nullObj() { static ObjPtr n = makeNull(); return n; }

bool Document::load(const std::string& path, std::string& error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { error = "cannot open " + path; return false; }
    std::stringstream ss;
    ss << in.rdbuf();
    data_ = ss.str();

    size_t hdr = data_.find("%PDF-");
    if (hdr == std::string::npos || hdr > 1024) { error = "not a PDF (missing %PDF- header)"; return false; }
    version_ = data_.substr(hdr + 5, 3);

    // Locate startxref near the end of the file.
    size_t tailStart = data_.size() > 2048 ? data_.size() - 2048 : 0;
    size_t sx = data_.rfind("startxref");
    if (sx != std::string::npos && sx >= tailStart) {
        Lexer lex(data_, sx + 9);
        Token t = lex.next();
        if (t.is(Token::Number)) lastStartXref_ = static_cast<long long>(t.number);
    }
    if (lastStartXref_ < 0 || !parseXrefChain(lastStartXref_)) {
        xrefBroken_ = true;
        scanAllObjects();
    }
    // Size hint from trailer; otherwise from whatever we found.
    int size = trailer_->get("Size")->intValue(0);
    if (!xref_.empty()) nextObjNum_ = std::max(nextObjNum_, xref_.rbegin()->first + 1);
    nextObjNum_ = std::max(nextObjNum_, size);
    if (nextObjNum_ < 1) nextObjNum_ = 1;

    if (!trailer_->has("Root")) {
        // Try to find the catalog by scanning.
        scanAllObjects();
        for (int n : knownNums_) {
            ObjPtr o = object(n);
            if (o->isDict() && o->get("Type")->isName("Catalog")) { trailer_->dict["Root"] = makeRef(n, 0); break; }
        }
        if (!trailer_->has("Root")) { error = "no document catalog found"; return false; }
    }
    return true;
}

// ---------------------------------------------------------------- xref parsing

bool Document::parseXrefChain(long long startOffset) {
    std::vector<long long> queue{startOffset};
    std::set<long long> seen;
    bool any = false;
    while (!queue.empty()) {
        long long off = queue.front();
        queue.erase(queue.begin());
        if (off < 0 || static_cast<size_t>(off) >= data_.size() || seen.count(off)) continue;
        seen.insert(off);
        Lexer lex(data_, static_cast<size_t>(off));
        lex.skipWhitespace();
        size_t pos = lex.pos();
        bool ok = data_.compare(pos, 4, "xref") == 0 ? parseXrefTable(pos, queue) : parseXrefStream(pos, queue);
        if (ok) any = true;
    }
    return any && (trailer_->has("Root") || !xref_.empty());
}

void Document::mergeTrailer(const ObjPtr& dict) {
    if (!dict || !dict->isDict()) return;
    for (const auto& [k, v] : dict->dict) {
        if (k == "Length" || k == "Filter" || k == "DecodeParms" || k == "W" || k == "Index" || k == "Type") continue;
        if (!trailer_->has(k)) trailer_->dict[k] = v;   // newest section wins
    }
}

bool Document::parseXrefTable(size_t pos, std::vector<long long>& more) {
    Lexer lex(data_, pos + 4);
    for (;;) {
        lex.skipWhitespace();
        if (data_.compare(lex.pos(), 7, "trailer") == 0) {
            Parser p(data_, lex.pos() + 7);
            ObjPtr tr = p.parse();
            if (tr && tr->isDict()) {
                mergeTrailer(tr);
                if (tr->get("XRefStm")->isNumber()) more.push_back(static_cast<long long>(tr->get("XRefStm")->number));
                if (tr->get("Prev")->isNumber()) more.push_back(static_cast<long long>(tr->get("Prev")->number));
            }
            return true;
        }
        Token a = lex.next();
        if (!a.is(Token::Number)) return !xref_.empty();
        Token b = lex.next();
        if (!b.is(Token::Number)) return false;
        int start = static_cast<int>(a.number);
        int count = static_cast<int>(b.number);
        if (count < 0 || count > 50'000'000) return false;
        for (int i = 0; i < count; ++i) {
            lex.skipWhitespace();
            // Entries are nominally 20 bytes, but parse by tokens to tolerate sloppy writers.
            Token o = lex.next(); Token g = lex.next(); Token t = lex.next();
            if (!o.is(Token::Number) || !g.is(Token::Number) || !t.is(Token::Keyword)) return false;
            int num = start + i;
            if (xref_.count(num)) continue;
            XrefEntry e;
            if (t.text == "n") { e.type = 1; e.field2 = static_cast<long long>(o.number); e.field3 = static_cast<int>(g.number); }
            else { e.type = 0; }
            xref_[num] = e;
        }
    }
}

bool Document::parseXrefStream(size_t pos, std::vector<long long>& more) {
    Parser p(data_, pos, [this](const Ref& r) { return object(r.num); });
    int num, gen; ObjPtr obj;
    if (!p.parseIndirect(num, gen, obj) || !obj->isStream()) return false;
    if (!obj->get("Type")->isName("XRef") && !obj->has("W")) return false;
    xrefStream_ = true;

    auto resolveLocal = [this](const ObjPtr& o) { return resolve(o); };
    std::string content = decodeStream(*obj, resolveLocal).data;
    ObjPtr w = resolve(obj->get("W"));
    if (!w->isArray()) return false;
    std::vector<int> widths;
    for (auto& x : w->array) widths.push_back(resolve(x)->intValue(0));
    while (widths.size() < 3) widths.push_back(0);
    size_t rowLen = 0;
    for (int x : widths) rowLen += static_cast<size_t>(std::max(0, x));
    if (rowLen == 0) return false;

    std::vector<std::pair<int, int>> index;
    ObjPtr idx = resolve(obj->get("Index"));
    if (idx->isArray()) {
        for (size_t i = 0; i + 1 < idx->array.size(); i += 2)
            index.emplace_back(resolve(idx->array[i])->intValue(0), resolve(idx->array[i + 1])->intValue(0));
    } else {
        index.emplace_back(0, resolve(obj->get("Size"))->intValue(0));
    }

    size_t off = 0;
    auto readField = [&](int width, long long def) {
        if (width == 0) return def;
        long long v = 0;
        for (int i = 0; i < width; ++i) v = (v << 8) | static_cast<unsigned char>(content[off++]);
        return v;
    };
    for (auto [start, count] : index) {
        for (int i = 0; i < count; ++i) {
            if (off + rowLen > content.size()) break;
            long long type = readField(widths[0], 1);
            long long f2 = readField(widths[1], 0);
            long long f3 = readField(widths[2], 0);
            int n = start + i;
            if (xref_.count(n)) continue;
            XrefEntry e; e.type = static_cast<int>(type); e.field2 = f2; e.field3 = static_cast<int>(f3);
            xref_[n] = e;
        }
    }
    mergeTrailer(makeDict(obj->dict));
    if (obj->get("Prev")->isNumber()) more.push_back(static_cast<long long>(obj->get("Prev")->number));
    return true;
}

// ---------------------------------------------------------------- object access

void Document::scanAllObjects() {
    if (scanned_) return;
    scanned_ = true;
    // Walk the file: find "N G obj", parse the object (which skips over stream bodies), repeat.
    size_t pos = 0;
    std::map<int, size_t> offsets;
    while (pos < data_.size()) {
        size_t o = data_.find("obj", pos);
        if (o == std::string::npos) break;
        // Walk backwards over "N G " to find the object header start.
        size_t q = o;
        auto back = [&](auto pred) { size_t n = 0; while (q > 0 && pred(data_[q - 1])) { --q; ++n; } return n; };
        size_t ws1 = back([](char c) { return isWhite(c); });
        size_t gd = back([](char c) { return c >= '0' && c <= '9'; });
        size_t ws2 = back([](char c) { return isWhite(c); });
        size_t nd = back([](char c) { return c >= '0' && c <= '9'; });
        bool headerOk = ws1 > 0 && gd > 0 && ws2 > 0 && nd > 0 && (q == 0 || !isRegular(data_[q - 1]));
        bool keywordOk = o + 3 >= data_.size() || !isRegular(data_[o + 3]);
        if (!headerOk || !keywordOk) { pos = o + 3; continue; }
        Parser p(data_, q, [this](const Ref& r) { return object(r.num); });
        int num, gen; ObjPtr obj;
        if (p.parseIndirect(num, gen, obj)) {
            offsets[num] = q;      // later definitions override earlier ones
            knownNums_.insert(num);
            pos = std::max(p.pos(), o + 3);
            if (xrefBroken_ || !xref_.count(num)) {
                XrefEntry e; e.type = 1; e.field2 = static_cast<long long>(q); e.field3 = gen;
                xref_[num] = e;
                cache_.erase(num);
            }
            // Objects inside object streams are also reachable.
            if (obj->isStream() && obj->get("Type")->isName("ObjStm")) {
                int n = resolve(obj->get("N"))->intValue(0);
                int first = resolve(obj->get("First"))->intValue(0);
                std::string content = streamData(obj);
                Lexer hl(content);
                for (int i = 0; i < n; ++i) {
                    Token a = hl.next(); Token b = hl.next();
                    if (!a.is(Token::Number) || !b.is(Token::Number)) break;
                    int inner = static_cast<int>(a.number);
                    knownNums_.insert(inner);
                    if (xrefBroken_ || !xref_.count(inner)) {
                        XrefEntry e; e.type = 2; e.field2 = num; e.field3 = i;
                        xref_[inner] = e;
                        cache_.erase(inner);
                    }
                }
                (void)first;
            }
        } else {
            pos = o + 3;
        }
    }
    if (xrefBroken_ && !trailer_->has("Root")) {
        // Pick up trailer dictionaries for Root/Info.
        size_t t = 0;
        while ((t = data_.find("trailer", t)) != std::string::npos) {
            Parser p(data_, t + 7);
            ObjPtr tr = p.parse();
            if (tr && tr->isDict()) for (auto& [k, v] : tr->dict) trailer_->dict[k] = v;  // later trailers win
            t += 7;
        }
        if (!trailer_->has("Root")) {
            for (int n : knownNums_) {
                ObjPtr o = object(n);
                if (o->isStream() && o->get("Type")->isName("XRef")) mergeTrailer(makeDict(o->dict));
            }
        }
    }
    if (!xref_.empty()) nextObjNum_ = std::max(nextObjNum_, xref_.rbegin()->first + 1);
}

const std::set<int>& Document::knownObjectNumbers() {
    if (knownNums_.empty()) for (auto& [n, e] : xref_) if (e.type != 0) knownNums_.insert(n);
    return knownNums_;
}

ObjPtr Document::parseAt(size_t offset, int expectedNum) {
    if (offset >= data_.size()) return nullptr;
    Parser p(data_, offset, [this](const Ref& r) { return object(r.num); });
    int num, gen; ObjPtr obj;
    if (!p.parseIndirect(num, gen, obj) || num != expectedNum) return nullptr;
    return obj;
}

ObjPtr Document::loadFromObjectStream(int streamNum, int index, int wantedNum) {
    auto it = objStmCache_.find(streamNum);
    if (it == objStmCache_.end()) {
        std::vector<std::pair<int, ObjPtr>> items;
        ObjPtr stm = object(streamNum);
        if (stm->isStream()) {
            int n = resolve(stm->get("N"))->intValue(0);
            int first = resolve(stm->get("First"))->intValue(0);
            std::string content = streamData(stm);
            Lexer hl(content);
            std::vector<std::pair<int, size_t>> header;
            for (int i = 0; i < n; ++i) {
                Token a = hl.next(); Token b = hl.next();
                if (!a.is(Token::Number) || !b.is(Token::Number)) break;
                header.emplace_back(static_cast<int>(a.number), static_cast<size_t>(first) + static_cast<size_t>(b.number));
            }
            for (auto& [num, off] : header) {
                if (off >= content.size()) { items.emplace_back(num, makeNull()); continue; }
                Parser p(content, off);
                ObjPtr o = p.parse();
                items.emplace_back(num, o ? o : makeNull());
            }
        }
        it = objStmCache_.emplace(streamNum, std::move(items)).first;
    }
    const auto& items = it->second;
    if (index >= 0 && static_cast<size_t>(index) < items.size() && items[index].first == wantedNum) return items[index].second;
    for (const auto& [num, o] : items) if (num == wantedNum) return o;
    return nullptr;
}

ObjPtr Document::object(int num) {
    auto c = cache_.find(num);
    if (c != cache_.end()) return c->second;
    cache_[num] = nullObj();   // guards against reference cycles while loading

    ObjPtr result;
    auto e = xref_.find(num);
    if (e != xref_.end()) {
        if (e->second.type == 1) result = parseAt(static_cast<size_t>(e->second.field2), num);
        else if (e->second.type == 2) result = loadFromObjectStream(static_cast<int>(e->second.field2), e->second.field3, num);
    }
    if (!result && !scanned_) {
        // Bad or missing xref entry: fall back to scanning the whole file once.
        xrefBroken_ = true;
        scanAllObjects();
        auto e2 = xref_.find(num);
        if (e2 != xref_.end()) {
            if (e2->second.type == 1) result = parseAt(static_cast<size_t>(e2->second.field2), num);
            else if (e2->second.type == 2) result = loadFromObjectStream(static_cast<int>(e2->second.field2), e2->second.field3, num);
        }
    }
    if (!result) result = nullObj();
    cache_[num] = result;
    return result;
}

ObjPtr Document::resolve(const ObjPtr& obj) {
    ObjPtr cur = obj ? obj : nullObj();
    for (int i = 0; i < 32 && cur->isRef(); ++i) cur = object(cur->ref.num);
    return cur->isRef() ? nullObj() : cur;
}

ObjPtr Document::catalog() { return resolve(trailer_->get("Root")); }
ObjPtr Document::info() { return resolve(trailer_->get("Info")); }
std::optional<Ref> Document::infoRef() const {
    ObjPtr r = trailer_->get("Info");
    if (r->isRef()) return r->ref;
    return std::nullopt;
}

std::string Document::streamData(const ObjPtr& stream, bool* complete) {
    ObjPtr s = resolve(stream);
    if (!s->isStream()) { if (complete) *complete = false; return {}; }
    FilterResult r = decodeStream(*s, [this](const ObjPtr& o) { return resolve(o); });
    if (complete) *complete = r.complete;
    return r.data;
}

// ---------------------------------------------------------------- page tree

void Document::collectPages(const ObjPtr& nodeRef, Ref parent, ObjPtr resources, ObjPtr mediaBox,
                            std::vector<PageInfo>& out, std::set<int>& visited, int depth) {
    if (depth > 64) return;
    Ref self{0, 0};
    if (nodeRef->isRef()) {
        self = nodeRef->ref;
        if (visited.count(self.num)) return;
        visited.insert(self.num);
    }
    ObjPtr node = resolve(nodeRef);
    if (!node->isDict()) return;
    if (node->has("Resources")) resources = node->get("Resources");
    if (node->has("MediaBox")) mediaBox = node->get("MediaBox");

    ObjPtr type = resolve(node->get("Type"));
    ObjPtr kids = resolve(node->get("Kids"));
    bool isPages = type->isName("Pages") || (kids->isArray() && !type->isName("Page"));
    if (isPages) {
        for (const auto& kid : kids->array) collectPages(kid, self, resources, mediaBox, out, visited, depth + 1);
    } else {
        PageInfo p;
        p.ref = self; p.dict = node; p.resources = resolve(resources); p.mediaBox = resolve(mediaBox); p.parent = parent;
        out.push_back(p);
    }
}

std::vector<PageInfo> Document::pages() {
    std::vector<PageInfo> out;
    std::set<int> visited;
    ObjPtr cat = catalog();
    ObjPtr pagesRef = cat->get("Pages");
    if (!resolve(pagesRef)->isDict()) {
        // Catalog missing /Pages: scan for page objects.
        scanAllObjects();
        for (int n : knownNums_) {
            ObjPtr o = object(n);
            if (o->isDict() && o->get("Type")->isName("Page")) {
                PageInfo p; p.ref = {n, 0}; p.dict = o; p.resources = resolve(o->get("Resources")); p.mediaBox = resolve(o->get("MediaBox"));
                p.parent = o->get("Parent")->isRef() ? o->get("Parent")->ref : Ref{0, 0};
                out.push_back(p);
            }
        }
        return out;
    }
    collectPages(pagesRef, Ref{0, 0}, makeNull(), makeNull(), out, visited, 0);
    return out;
}

// ---------------------------------------------------------------- modification

int Document::allocateObject() { return nextObjNum_++; }

void Document::setObject(int num, int gen, ObjPtr value) {
    for (auto& u : updates_) if (u.num == num) { u.gen = gen; u.value = value; cache_[num] = value; return; }
    updates_.push_back({num, gen, value});
    cache_[num] = value;
    nextObjNum_ = std::max(nextObjNum_, num + 1);
}

bool Document::save(const std::string& path, std::string& error) {
    if (isEncrypted()) { error = "encrypted PDFs cannot be modified"; return false; }
    std::string out = data_;
    if (out.empty() || out.back() != '\n') out += '\n';

    std::vector<Update> ups = updates_;
    std::sort(ups.begin(), ups.end(), [](const Update& a, const Update& b) { return a.num < b.num; });
    std::map<int, std::pair<size_t, int>> offsets;   // num -> (offset, gen)
    for (const auto& u : ups) {
        offsets[u.num] = {out.size(), u.gen};
        out += std::to_string(u.num) + " " + std::to_string(u.gen) + " obj\n";
        out += serialize(u.value);
        out += "\nendobj\n";
    }

    ObjPtr root = trailer_->get("Root");
    ObjPtr infoR = newInfo_ ? makeRef(newInfo_->num, newInfo_->gen) : trailer_->get("Info");
    ObjPtr ids = trailer_->get("ID");
    int size = nextObjNum_;
    size_t xrefPos = out.size();

    if (!xrefStream_) {
        // Classic cross-reference table with one subsection per run of consecutive numbers.
        out += "xref\n";
        auto it = offsets.begin();
        while (it != offsets.end()) {
            auto runStart = it;
            int count = 0;
            int expect = it->first;
            while (it != offsets.end() && it->first == expect) { ++it; ++expect; ++count; }
            out += std::to_string(runStart->first) + " " + std::to_string(count) + "\n";
            for (auto r = runStart; r != it; ++r) {
                char buf[32];
                std::snprintf(buf, sizeof buf, "%010zu %05d n \n", r->second.first, r->second.second);
                out += buf;
            }
        }
        out += "trailer\n<< /Size " + std::to_string(size) + " /Root " + serialize(root);
        if (!infoR->isNull()) out += " /Info " + serialize(infoR);
        if (ids->isArray()) out += " /ID " + serialize(ids);
        out += " /Prev " + std::to_string(lastStartXref_) + " >>\n";
    } else {
        // Cross-reference stream: fields W [1 8 2], uncompressed.
        int xnum = size++;
        offsets[xnum] = {xrefPos, 0};
        std::string rows;
        std::vector<ObjPtr> index;
        auto it = offsets.begin();
        while (it != offsets.end()) {
            int start = it->first, expect = start, count = 0;
            while (it != offsets.end() && it->first == expect) {
                unsigned char row[11];
                row[0] = 1;
                uint64_t off = it->second.first;
                for (int k = 0; k < 8; ++k) row[1 + k] = static_cast<unsigned char>((off >> (8 * (7 - k))) & 0xFF);
                row[9] = static_cast<unsigned char>((it->second.second >> 8) & 0xFF);
                row[10] = static_cast<unsigned char>(it->second.second & 0xFF);
                rows.append(reinterpret_cast<char*>(row), 11);
                ++it; ++expect; ++count;
            }
            index.push_back(makeInt(start));
            index.push_back(makeInt(count));
        }
        std::map<std::string, ObjPtr> d;
        d["Type"] = makeName("XRef");
        d["Size"] = makeInt(size);
        d["W"] = makeArray({makeInt(1), makeInt(8), makeInt(2)});
        d["Index"] = makeArray(index);
        d["Root"] = root;
        if (!infoR->isNull()) d["Info"] = infoR;
        if (ids->isArray()) d["ID"] = ids;
        d["Prev"] = makeInt(lastStartXref_);
        out += std::to_string(xnum) + " 0 obj\n" + serialize(makeStream(d, rows)) + "\nendobj\n";
    }
    out += "startxref\n" + std::to_string(xrefPos) + "\n%%EOF\n";

    std::ofstream f(path, std::ios::binary | std::ios::trunc);
    if (!f) { error = "cannot write " + path; return false; }
    f.write(out.data(), static_cast<std::streamsize>(out.size()));
    if (!f) { error = "write failed for " + path; return false; }
    return true;
}

}  // namespace anyfile::pdf
