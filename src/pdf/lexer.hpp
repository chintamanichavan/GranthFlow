// Tokenizer for PDF syntax. Shared by the object parser, content streams and CMaps.
#pragma once
#include <string>
#include <string_view>

namespace anyfile::pdf {

inline bool isWhite(char c) { return c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f' || c == '\0'; }
inline bool isDelim(char c) {
    return c == '(' || c == ')' || c == '<' || c == '>' || c == '[' || c == ']' || c == '{' || c == '}' || c == '/' || c == '%';
}
inline bool isRegular(char c) { return !isWhite(c) && !isDelim(c); }

struct Token {
    enum Kind { End, Number, String, Name, ArrayOpen, ArrayClose, DictOpen, DictClose, BraceOpen, BraceClose, Keyword };
    Kind kind = End;
    std::string text;   // String bytes (decoded), Name (no '/'), Keyword
    double number = 0;
    bool isInteger = false;
    bool is(Kind k) const { return kind == k; }
    bool isKeyword(const char* kw) const { return kind == Keyword && text == kw; }
};

class Lexer {
public:
    explicit Lexer(std::string_view data, size_t pos = 0) : d_(data), p_(pos) {}

    Token next();
    Token peek();
    size_t pos() const { return p_; }
    void seek(size_t p) { p_ = p < d_.size() ? p : d_.size(); }
    std::string_view data() const { return d_; }
    void skipWhitespace();   // whitespace and % comments
    bool atEnd() { skipWhitespace(); return p_ >= d_.size(); }

private:
    Token readLiteralString();
    Token readHexString();
    Token readName();
    Token readNumberOrKeyword();
    std::string_view d_;
    size_t p_;
};

}  // namespace anyfile::pdf
