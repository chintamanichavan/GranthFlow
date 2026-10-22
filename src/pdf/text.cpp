#include "text.hpp"

#include <cmath>
#include <set>
#include <vector>

#include "lexer.hpp"
#include "filters.hpp"
#include "parser.hpp"

namespace anyfile::pdf {

// ---------------------------------------------------------------- encodings

static void appendUtf8(std::string& out, uint32_t cp) {
    if (cp < 0x80) out += static_cast<char>(cp);
    else if (cp < 0x800) { out += static_cast<char>(0xC0 | (cp >> 6)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += static_cast<char>(0xE0 | (cp >> 12)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else { out += static_cast<char>(0xF0 | (cp >> 18)); out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
}

static std::string utf16beToUtf8(const std::string& s) {
    std::string out;
    for (size_t i = 0; i + 1 < s.size(); i += 2) {
        uint32_t u = (static_cast<unsigned char>(s[i]) << 8) | static_cast<unsigned char>(s[i + 1]);
        if (u >= 0xD800 && u <= 0xDBFF && i + 3 < s.size()) {
            uint32_t lo = (static_cast<unsigned char>(s[i + 2]) << 8) | static_cast<unsigned char>(s[i + 3]);
            u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00);
            i += 2;
        }
        appendUtf8(out, u);
    }
    if (s.size() == 1) appendUtf8(out, static_cast<unsigned char>(s[0]));
    return out;
}

// WinAnsi 0x80-0x9F differ from Latin-1; the rest match.
static const uint32_t kWinAnsiHigh[32] = {
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178};

static const uint32_t kMacRomanHigh[128] = {
    0xC4, 0xC5, 0xC7, 0xC9, 0xD1, 0xD6, 0xDC, 0xE1, 0xE0, 0xE2, 0xE4, 0xE3, 0xE5, 0xE7, 0xE9, 0xE8,
    0xEA, 0xEB, 0xED, 0xEC, 0xEE, 0xEF, 0xF1, 0xF3, 0xF2, 0xF4, 0xF6, 0xF5, 0xFA, 0xF9, 0xFB, 0xFC,
    0x2020, 0xB0, 0xA2, 0xA3, 0xA7, 0x2022, 0xB6, 0xDF, 0xAE, 0xA9, 0x2122, 0xB4, 0xA8, 0x2260, 0xC6, 0xD8,
    0x221E, 0xB1, 0x2264, 0x2265, 0xA5, 0xB5, 0x2202, 0x2211, 0x220F, 0x3C0, 0x222B, 0xAA, 0xBA, 0x3A9, 0xE6, 0xF8,
    0xBF, 0xA1, 0xAC, 0x221A, 0x192, 0x2248, 0x2206, 0xAB, 0xBB, 0x2026, 0xA0, 0xC0, 0xC3, 0xD5, 0x152, 0x153,
    0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0xF7, 0x25CA, 0xFF, 0x178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0xB7, 0x201A, 0x201E, 0x2030, 0xC2, 0xCA, 0xC1, 0xCB, 0xC8, 0xCD, 0xCE, 0xCF, 0xCC, 0xD3, 0xD4,
    0xF8FF, 0xD2, 0xDA, 0xDB, 0xD9, 0x131, 0x2C6, 0x2DC, 0xAF, 0x2D8, 0x2D9, 0x2DA, 0xB8, 0x2DD, 0x2DB, 0x2C7};

std::string FontDecoder::decode(const std::string& bytes, ExtractStats* stats) const {
    std::string out;
    int width = codeBytes < 1 ? 1 : codeBytes;
    for (size_t i = 0; i < bytes.size(); i += static_cast<size_t>(width)) {
        int code = 0;
        for (int k = 0; k < width; ++k) code = (code << 8) | (i + k < bytes.size() ? static_cast<unsigned char>(bytes[i + k]) : 0);
        auto it = toUnicode.find(code);
        if (it != toUnicode.end()) { out += it->second; continue; }
        if (hasToUnicode && width > 1) { if (stats) ++stats->unmappedGlyphs; continue; }
        if (width == 1) {
            auto c = static_cast<uint32_t>(code);
            if (c < 0x80) { out += static_cast<char>(c); continue; }
            if (encoding == "MacRomanEncoding") { appendUtf8(out, kMacRomanHigh[c - 0x80]); continue; }
            if (c < 0xA0) { uint32_t m = kWinAnsiHigh[c - 0x80]; if (m) appendUtf8(out, m); continue; }
            appendUtf8(out, c);  // Latin-1 / WinAnsi upper range
        } else {
            if (stats) ++stats->unmappedGlyphs;
        }
    }
    return out;
}

// ---------------------------------------------------------------- CMap (ToUnicode) parsing

static void parseToUnicode(const std::string& cmap, FontDecoder& fd) {
    Parser p(cmap);
    std::vector<ObjPtr> stack;
    std::set<int> codeLengths;
    auto hexInt = [](const std::string& s) { int v = 0; for (unsigned char c : s) v = (v << 8) | c; return v; };
    while (true) {
        ObjPtr o = p.parse();
        if (!o) break;
        if (!o->isOperator()) { stack.push_back(o); if (stack.size() > 64) stack.erase(stack.begin()); continue; }
        const std::string& op = o->str;
        if (op == "begincodespacerange") {
            for (;;) {
                ObjPtr lo = p.parse(); if (!lo || lo->isOperator()) break;
                ObjPtr hi = p.parse(); if (!hi || hi->isOperator()) break;
                if (lo->isString()) codeLengths.insert(static_cast<int>(lo->str.size()));
            }
        } else if (op == "beginbfchar") {
            for (;;) {
                ObjPtr src = p.parse(); if (!src || src->isOperator()) break;
                ObjPtr dst = p.parse(); if (!dst || dst->isOperator()) break;
                if (!src->isString()) continue;
                codeLengths.insert(static_cast<int>(src->str.size()));
                if (dst->isString()) fd.toUnicode[hexInt(src->str)] = utf16beToUtf8(dst->str);
                else if (dst->isName()) fd.toUnicode[hexInt(src->str)] = dst->str;
            }
        } else if (op == "beginbfrange") {
            for (;;) {
                ObjPtr lo = p.parse(); if (!lo || lo->isOperator()) break;
                ObjPtr hi = p.parse(); if (!hi || hi->isOperator()) break;
                ObjPtr dst = p.parse(); if (!dst || dst->isOperator()) break;
                if (!lo->isString() || !hi->isString()) continue;
                codeLengths.insert(static_cast<int>(lo->str.size()));
                int a = hexInt(lo->str), b = hexInt(hi->str);
                if (b < a || b - a > 65535) continue;
                if (dst->isArray()) {
                    for (int c = a; c <= b && static_cast<size_t>(c - a) < dst->array.size(); ++c)
                        if (dst->array[c - a]->isString()) fd.toUnicode[c] = utf16beToUtf8(dst->array[c - a]->str);
                } else if (dst->isString()) {
                    std::string base = dst->str;
                    for (int c = a; c <= b; ++c) {
                        fd.toUnicode[c] = utf16beToUtf8(base);
                        // increment the last UTF-16 code unit
                        for (int k = static_cast<int>(base.size()) - 1; k >= 0; --k) {
                            unsigned char v = static_cast<unsigned char>(base[k]) + 1;
                            base[k] = static_cast<char>(v);
                            if (v != 0) break;
                        }
                    }
                }
            }
        }
    }
    if (!codeLengths.empty()) fd.codeBytes = *codeLengths.rbegin();
    fd.hasToUnicode = !fd.toUnicode.empty();
}

FontDecoder buildFontDecoder(Document& doc, const ObjPtr& fontRef) {
    FontDecoder fd;
    ObjPtr font = doc.resolve(fontRef);
    if (!font->isDict()) return fd;
    ObjPtr subtype = doc.resolve(font->get("Subtype"));
    if (subtype->isName("Type0")) fd.codeBytes = 2;
    ObjPtr enc = doc.resolve(font->get("Encoding"));
    if (enc->isName()) fd.encoding = enc->str;
    else if (enc->isDict()) fd.encoding = doc.resolve(enc->get("BaseEncoding"))->str;
    ObjPtr tu = doc.resolve(font->get("ToUnicode"));
    if (tu->isStream()) {
        int before = fd.codeBytes;
        parseToUnicode(doc.streamData(tu), fd);
        if (subtype->isName("Type0") && fd.codeBytes < 2) fd.codeBytes = before;  // trust the font type over odd CMaps
    }
    return fd;
}

// ---------------------------------------------------------------- content stream interpreter

namespace {

struct TextState {
    std::string out;
    double lastX = 0, lastY = 0;
    bool haveLast = false;
    double tm[6] = {1, 0, 0, 1, 0, 0};
    double tlm[6] = {1, 0, 0, 1, 0, 0};
    double fontSize = 10;
    double leading = 0;
    std::map<std::string, FontDecoder> fontCache;
    const FontDecoder* font = nullptr;
    int depth = 0;
};

void newline(TextState& st) {
    if (!st.out.empty() && st.out.back() != '\n') st.out += '\n';
}

void setMatrix(double* m, double a, double b, double c, double d, double e, double f) {
    m[0] = a; m[1] = b; m[2] = c; m[3] = d; m[4] = e; m[5] = f;
}

// Note movement of the text position; emit newline or space when it indicates one.
void moved(TextState& st) {
    double x = st.tm[4], y = st.tm[5];
    if (st.haveLast) {
        double dy = std::fabs(y - st.lastY);
        if (dy > st.fontSize * 0.5) newline(st);
        else if (x - st.lastX > st.fontSize * 0.25 && !st.out.empty() && st.out.back() != ' ' && st.out.back() != '\n') st.out += ' ';
    }
    st.lastX = x; st.lastY = y; st.haveLast = true;
}

void runContent(Document& doc, const std::string& content, const ObjPtr& resources, TextState& st, ExtractStats* stats);

void showText(Document& doc, const std::string& bytes, const ObjPtr& resources, TextState& st, ExtractStats* stats) {
    (void)doc; (void)resources;
    moved(st);
    std::string s = st.font ? st.font->decode(bytes, stats) : FontDecoder{}.decode(bytes, stats);
    st.out += s;
    // Approximate advance so later Td/Tm can be judged relative to where the text ended.
    double advance = static_cast<double>(s.size()) * st.fontSize * 0.5;
    double scaleX = std::sqrt(st.tm[0] * st.tm[0] + st.tm[1] * st.tm[1]);
    st.lastX += advance * (scaleX == 0 ? 1 : scaleX);
    st.tm[4] = st.lastX;
}

void selectFont(Document& doc, const std::string& name, const ObjPtr& resources, TextState& st) {
    auto it = st.fontCache.find(name);
    if (it == st.fontCache.end()) {
        ObjPtr fonts = doc.resolve(doc.resolve(resources)->get("Font"));
        it = st.fontCache.emplace(name, buildFontDecoder(doc, fonts->get(name))).first;
    }
    st.font = &it->second;
}

void runContent(Document& doc, const std::string& content, const ObjPtr& resources, TextState& st, ExtractStats* stats) {
    if (st.depth > 12) return;
    Parser p(content);
    std::vector<ObjPtr> stack;
    auto num = [&](size_t idxFromEnd) {
        return stack.size() > idxFromEnd ? stack[stack.size() - 1 - idxFromEnd]->numValue() : 0.0;
    };
    for (;;) {
        ObjPtr o = p.parse();
        if (!o) break;
        if (!o->isOperator()) {
            stack.push_back(o);
            if (stack.size() > 64) stack.erase(stack.begin());
            continue;
        }
        const std::string& op = o->str;
        if (op == "BT") {
            setMatrix(st.tm, 1, 0, 0, 1, 0, 0); setMatrix(st.tlm, 1, 0, 0, 1, 0, 0);
        } else if (op == "ET") {
            newline(st);
        } else if (op == "Tf") {
            if (stack.size() >= 2 && stack[stack.size() - 2]->isName()) {
                st.fontSize = std::fabs(num(0));
                if (st.fontSize == 0) st.fontSize = 10;
                selectFont(doc, stack[stack.size() - 2]->str, resources, st);
            }
        } else if (op == "TL") {
            st.leading = num(0);
        } else if (op == "Td" || op == "TD") {
            double tx = num(1), ty = num(0);
            if (op == "TD") st.leading = -ty;
            st.tlm[4] += tx * st.tlm[0] + ty * st.tlm[2];
            st.tlm[5] += tx * st.tlm[1] + ty * st.tlm[3];
            for (int i = 0; i < 6; ++i) st.tm[i] = st.tlm[i];
        } else if (op == "Tm") {
            if (stack.size() >= 6) {
                setMatrix(st.tlm, num(5), num(4), num(3), num(2), num(1), num(0));
                for (int i = 0; i < 6; ++i) st.tm[i] = st.tlm[i];
            }
        } else if (op == "T*") {
            st.tlm[4] += -st.leading * st.tlm[2];
            st.tlm[5] += -st.leading * st.tlm[3];
            for (int i = 0; i < 6; ++i) st.tm[i] = st.tlm[i];
            newline(st);
        } else if (op == "Tj") {
            if (!stack.empty() && stack.back()->isString()) showText(doc, stack.back()->str, resources, st, stats);
        } else if (op == "'" || op == "\"") {
            st.tlm[4] += -st.leading * st.tlm[2];
            st.tlm[5] += -st.leading * st.tlm[3];
            for (int i = 0; i < 6; ++i) st.tm[i] = st.tlm[i];
            newline(st);
            if (!stack.empty() && stack.back()->isString()) showText(doc, stack.back()->str, resources, st, stats);
        } else if (op == "TJ") {
            if (!stack.empty() && stack.back()->isArray()) {
                for (const auto& el : stack.back()->array) {
                    if (el->isString()) showText(doc, el->str, resources, st, stats);
                    else if (el->isNumber() && el->number < -180 && !st.out.empty() && st.out.back() != ' ') st.out += ' ';
                }
            }
        } else if (op == "Do") {
            if (!stack.empty() && stack.back()->isName()) {
                ObjPtr xobjs = doc.resolve(doc.resolve(resources)->get("XObject"));
                ObjPtr xo = doc.resolve(xobjs->get(stack.back()->str));
                if (xo->isStream() && doc.resolve(xo->get("Subtype"))->isName("Form")) {
                    bool complete = true;
                    std::string inner = doc.streamData(xo, &complete);
                    if (!complete && stats) ++stats->unsupportedStreams;
                    ObjPtr res = xo->has("Resources") ? xo->get("Resources") : resources;
                    std::map<std::string, FontDecoder> savedFonts = std::move(st.fontCache);
                    const FontDecoder* savedFont = st.font;
                    st.fontCache.clear(); st.font = nullptr; ++st.depth;
                    runContent(doc, inner, res, st, stats);
                    --st.depth; st.fontCache = std::move(savedFonts); st.font = savedFont;
                }
            }
        } else if (op == "BI") {
            // Inline image: skip to EI.
            std::string_view d = p.lexer().data();
            size_t e = d.find("EI", p.pos());
            while (e != std::string_view::npos && !(e + 2 >= d.size() || isWhite(d[e + 2])) ) e = d.find("EI", e + 2);
            p.seek(e == std::string_view::npos ? d.size() : e + 2);
        }
        stack.clear();
    }
}

std::string pageContent(Document& doc, const PageInfo& page, ExtractStats* stats) {
    ObjPtr contents = doc.resolve(page.dict->get("Contents"));
    std::string all;
    auto add = [&](const ObjPtr& s) {
        bool complete = true;
        all += doc.streamData(s, &complete);
        all += '\n';
        if (!complete && stats) ++stats->unsupportedStreams;
    };
    if (contents->isStream()) add(contents);
    else if (contents->isArray()) for (const auto& c : contents->array) add(c);
    return all;
}

}  // namespace

std::string extractPageText(Document& doc, const PageInfo& page, ExtractStats* stats) {
    TextState st;
    runContent(doc, pageContent(doc, page, stats), page.resources, st, stats);
    // Collapse runs of blank lines and trailing spaces.
    std::string out;
    int blank = 0;
    size_t i = 0;
    while (i < st.out.size()) {
        size_t e = st.out.find('\n', i);
        if (e == std::string::npos) e = st.out.size();
        std::string line = st.out.substr(i, e - i);
        while (!line.empty() && line.back() == ' ') line.pop_back();
        if (line.empty()) { if (++blank <= 1 && !out.empty()) out += '\n'; }
        else { blank = 0; out += line; out += '\n'; }
        i = e + 1;
    }
    return out;
}

// ---------------------------------------------------------------- replacement

// Rewrites string operands in content so that `from` becomes `to`. Works on the raw token text so
// that everything else in the stream is preserved byte-for-byte.
static std::string rewriteContent(const std::string& content, const std::string& from, const std::string& to, bool all, int& count) {
    std::string out;
    Lexer lex(content);
    size_t last = 0;
    bool done = false;
    for (;;) {
        lex.skipWhitespace();
        size_t start = lex.pos();
        Token t = lex.next();
        if (t.is(Token::End)) break;
        if (t.is(Token::String) && !done) {
            size_t pos = t.text.find(from);
            if (pos != std::string::npos) {
                std::string s = t.text;
                while (pos != std::string::npos) {
                    s.replace(pos, from.size(), to);
                    ++count;
                    if (!all) { done = true; break; }
                    pos = s.find(from, pos + to.size());
                }
                out.append(content, last, start - last);
                out += serialize(makeString(s));
                last = lex.pos();
            }
        } else if (t.isKeyword("BI")) {
            size_t e = content.find("EI", lex.pos());
            lex.seek(e == std::string::npos ? content.size() : e + 2);
        }
    }
    out.append(content, last, std::string::npos);
    return out;
}

int replaceTextOnPage(Document& doc, const PageInfo& page, const std::string& from, const std::string& to, bool all) {
    ObjPtr contentsRaw = page.dict->get("Contents");
    ObjPtr contents = doc.resolve(contentsRaw);
    std::vector<ObjPtr> streamRefs;
    if (contents->isStream() && contentsRaw->isRef()) streamRefs.push_back(contentsRaw);
    else if (contents->isArray()) for (const auto& c : contents->array) if (c->isRef()) streamRefs.push_back(c);
    int total = 0;
    for (const auto& ref : streamRefs) {
        if (total > 0 && !all) break;
        ObjPtr s = doc.resolve(ref);
        bool complete = true;
        std::string content = doc.streamData(s, &complete);
        if (!complete) continue;
        int count = 0;
        std::string rewritten = rewriteContent(content, from, to, all, count);
        if (count == 0) continue;
        total += count;
        std::map<std::string, ObjPtr> d;   // keep non-filter entries
        for (const auto& [k, v] : s->dict)
            if (k != "Filter" && k != "DecodeParms" && k != "DP" && k != "F" && k != "Length") d[k] = v;
        d["Filter"] = makeName("FlateDecode");
        doc.setObject(ref->ref.num, ref->ref.gen, makeStream(d, flateEncode(rewritten)));
    }
    return total;
}

}  // namespace anyfile::pdf
