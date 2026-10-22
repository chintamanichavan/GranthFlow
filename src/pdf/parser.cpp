#include "parser.hpp"

namespace anyfile::pdf {

ObjPtr Parser::parse() {
    Token t = lex_.next();
    if (t.is(Token::End)) return nullptr;
    return parseFromToken(t, 0);
}

ObjPtr Parser::parseFromToken(const Token& t, int depth) {
    if (depth > 256) return makeNull();
    switch (t.kind) {
        case Token::End: return nullptr;
        case Token::Number: {
            if (t.isInteger && t.number >= 0) {
                // Lookahead for "gen R" to form a reference.
                size_t save = lex_.pos();
                Token t2 = lex_.next();
                if (t2.is(Token::Number) && t2.isInteger && t2.number >= 0) {
                    Token t3 = lex_.next();
                    if (t3.isKeyword("R")) return makeRef(static_cast<int>(t.number), static_cast<int>(t2.number));
                }
                lex_.seek(save);
            }
            return makeNumber(t.number, t.isInteger);
        }
        case Token::String: return makeString(t.text);
        case Token::Name: return makeName(t.text);
        case Token::ArrayOpen: {
            auto arr = makeArray();
            for (;;) {
                Token n = lex_.next();
                if (n.is(Token::End) || n.is(Token::ArrayClose)) break;
                if (n.is(Token::DictClose)) continue;  // malformed, skip
                if (n.isKeyword("endobj") || n.isKeyword("endstream")) { break; }
                auto item = parseFromToken(n, depth + 1);
                if (item) arr->array.push_back(item);
            }
            return arr;
        }
        case Token::DictOpen: {
            auto d = makeDict();
            for (;;) {
                Token k = lex_.next();
                if (k.is(Token::End) || k.is(Token::DictClose)) break;
                if (k.isKeyword("endobj") || k.isKeyword("stream")) { lex_.seek(lex_.pos() - k.text.size()); break; }
                if (!k.is(Token::Name)) {
                    // Skip a stray value so we stay in sync.
                    parseFromToken(k, depth + 1);
                    continue;
                }
                Token v = lex_.next();
                if (v.is(Token::DictClose) || v.is(Token::End)) break;
                auto val = parseFromToken(v, depth + 1);
                if (val) d->dict[k.text] = val;
            }
            // A dictionary followed by the "stream" keyword is a stream object.
            size_t save = lex_.pos();
            Token n = lex_.next();
            if (n.isKeyword("stream")) return readStreamBody(d);
            lex_.seek(save);
            return d;
        }
        case Token::ArrayClose:
        case Token::DictClose:
        case Token::BraceOpen:
        case Token::BraceClose:
            return makeOperator(t.kind == Token::BraceOpen ? "{" : t.kind == Token::BraceClose ? "}" : t.kind == Token::ArrayClose ? "]" : ">>");
        case Token::Keyword:
            if (t.text == "true") return makeBool(true);
            if (t.text == "false") return makeBool(false);
            if (t.text == "null") return makeNull();
            return makeOperator(t.text);
    }
    return makeNull();
}

ObjPtr Parser::readStreamBody(ObjPtr dict) {
    std::string_view d = lex_.data();
    size_t p = lex_.pos();
    // After "stream" comes CRLF or LF (tolerate spaces before it).
    while (p < d.size() && d[p] == ' ') ++p;
    if (p < d.size() && d[p] == '\r') ++p;
    if (p < d.size() && d[p] == '\n') ++p;
    size_t start = p;

    long long length = -1;
    ObjPtr lenObj = dict->get("Length");
    if (lenObj->isRef() && resolver_) lenObj = resolver_(lenObj->ref);
    if (lenObj && lenObj->isNumber()) length = static_cast<long long>(lenObj->number);

    auto validEnd = [&](size_t end) {
        if (end > d.size()) return false;
        size_t q = end;
        while (q < d.size() && isWhite(d[q])) ++q;
        return d.substr(q, 9) == "endstream";
    };

    size_t end;
    if (length >= 0 && validEnd(start + static_cast<size_t>(length))) {
        end = start + static_cast<size_t>(length);
    } else {
        // Length missing or wrong: search for the endstream keyword.
        size_t e = d.find("endstream", start);
        if (e == std::string_view::npos) e = d.size();
        end = e;
        if (end > start && d[end - 1] == '\n') --end;
        if (end > start && d[end - 1] == '\r') --end;
    }
    auto s = makeStream(dict->dict, std::string(d.substr(start, end - start)));
    size_t q = end;
    while (q < d.size() && isWhite(d[q])) ++q;
    if (d.substr(q, 9) == "endstream") q += 9;
    lex_.seek(q);
    return s;
}

bool Parser::parseIndirect(int& num, int& gen, ObjPtr& out) {
    Token a = lex_.next();
    Token b = lex_.next();
    Token c = lex_.next();
    if (!a.is(Token::Number) || !b.is(Token::Number) || !c.isKeyword("obj")) return false;
    num = static_cast<int>(a.number);
    gen = static_cast<int>(b.number);
    Token t = lex_.next();
    if (t.isKeyword("endobj")) { out = makeNull(); return true; }
    out = parseFromToken(t, 0);
    if (!out) out = makeNull();
    size_t save = lex_.pos();
    Token e = lex_.next();
    if (!e.isKeyword("endobj")) lex_.seek(save);
    return true;
}

}  // namespace anyfile::pdf
