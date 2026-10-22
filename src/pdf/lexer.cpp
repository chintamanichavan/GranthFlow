#include "lexer.hpp"

#include <cstdlib>

namespace anyfile::pdf {

void Lexer::skipWhitespace() {
    while (p_ < d_.size()) {
        char c = d_[p_];
        if (isWhite(c)) {
            ++p_;
        } else if (c == '%') {
            while (p_ < d_.size() && d_[p_] != '\n' && d_[p_] != '\r') ++p_;
        } else {
            break;
        }
    }
}

Token Lexer::peek() {
    size_t save = p_;
    Token t = next();
    p_ = save;
    return t;
}

Token Lexer::next() {
    skipWhitespace();
    Token t;
    if (p_ >= d_.size()) return t;
    char c = d_[p_];
    switch (c) {
        case '[': ++p_; t.kind = Token::ArrayOpen; return t;
        case ']': ++p_; t.kind = Token::ArrayClose; return t;
        case '{': ++p_; t.kind = Token::BraceOpen; return t;
        case '}': ++p_; t.kind = Token::BraceClose; return t;
        case '(': return readLiteralString();
        case '/': return readName();
        case ')': ++p_; t.kind = Token::Keyword; t.text = ")"; return t;  // stray, tolerated
        case '<':
            if (p_ + 1 < d_.size() && d_[p_ + 1] == '<') { p_ += 2; t.kind = Token::DictOpen; return t; }
            return readHexString();
        case '>':
            if (p_ + 1 < d_.size() && d_[p_ + 1] == '>') { p_ += 2; t.kind = Token::DictClose; return t; }
            ++p_; t.kind = Token::Keyword; t.text = ">"; return t;
        default: return readNumberOrKeyword();
    }
}

Token Lexer::readLiteralString() {
    Token t; t.kind = Token::String;
    ++p_;  // '('
    int depth = 1;
    while (p_ < d_.size()) {
        char c = d_[p_++];
        if (c == '\\') {
            if (p_ >= d_.size()) break;
            char e = d_[p_++];
            switch (e) {
                case 'n': t.text += '\n'; break;
                case 'r': t.text += '\r'; break;
                case 't': t.text += '\t'; break;
                case 'b': t.text += '\b'; break;
                case 'f': t.text += '\f'; break;
                case '\r': if (p_ < d_.size() && d_[p_] == '\n') ++p_; break;  // line continuation
                case '\n': break;
                default:
                    if (e >= '0' && e <= '7') {
                        int v = e - '0';
                        for (int i = 0; i < 2 && p_ < d_.size() && d_[p_] >= '0' && d_[p_] <= '7'; ++i) v = v * 8 + (d_[p_++] - '0');
                        t.text += static_cast<char>(v & 0xFF);
                    } else {
                        t.text += e;
                    }
            }
        } else if (c == '(') {
            ++depth; t.text += c;
        } else if (c == ')') {
            if (--depth == 0) break;
            t.text += c;
        } else {
            t.text += c;
        }
    }
    return t;
}

static int hexVal(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

Token Lexer::readHexString() {
    Token t; t.kind = Token::String;
    ++p_;  // '<'
    int hi = -1;
    while (p_ < d_.size() && d_[p_] != '>') {
        int v = hexVal(d_[p_++]);
        if (v < 0) continue;
        if (hi < 0) { hi = v; } else { t.text += static_cast<char>(hi * 16 + v); hi = -1; }
    }
    if (hi >= 0) t.text += static_cast<char>(hi * 16);
    if (p_ < d_.size()) ++p_;  // '>'
    return t;
}

Token Lexer::readName() {
    Token t; t.kind = Token::Name;
    ++p_;  // '/'
    while (p_ < d_.size() && isRegular(d_[p_])) {
        char c = d_[p_++];
        if (c == '#' && p_ + 1 < d_.size()) {
            int a = hexVal(d_[p_]), b = hexVal(d_[p_ + 1]);
            if (a >= 0 && b >= 0) { t.text += static_cast<char>(a * 16 + b); p_ += 2; continue; }
        }
        t.text += c;
    }
    return t;
}

Token Lexer::readNumberOrKeyword() {
    Token t;
    size_t start = p_;
    while (p_ < d_.size() && isRegular(d_[p_])) ++p_;
    if (p_ == start) ++p_;  // unknown delimiter: consume one char to guarantee progress
    t.text = std::string(d_.substr(start, p_ - start));
    // Number: optional sign(s), digits, optional '.' and digits. PDF allows forms like "--5" and ".5".
    size_t i = 0;
    while (i < t.text.size() && (t.text[i] == '+' || t.text[i] == '-')) ++i;
    bool digits = false, dot = false, ok = true;
    for (; i < t.text.size(); ++i) {
        char c = t.text[i];
        if (c >= '0' && c <= '9') digits = true;
        else if (c == '.' && !dot) dot = true;
        else { ok = false; break; }
    }
    if (ok && digits) {
        t.kind = Token::Number;
        std::string clean;
        bool neg = false;
        size_t j = 0;
        while (j < t.text.size() && (t.text[j] == '+' || t.text[j] == '-')) { if (t.text[j] == '-') neg = !neg; ++j; }
        clean = t.text.substr(j);
        t.number = std::strtod(clean.c_str(), nullptr);
        if (neg) t.number = -t.number;
        t.isInteger = !dot;
    } else {
        t.kind = Token::Keyword;
    }
    return t;
}

}  // namespace anyfile::pdf
