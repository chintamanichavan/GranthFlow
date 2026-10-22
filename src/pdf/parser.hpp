// Builds Objects from tokens. Handles "n g R" references and stream bodies.
#pragma once
#include <functional>

#include "lexer.hpp"
#include "object.hpp"

namespace anyfile::pdf {

class Parser {
public:
    // Resolver lets the parser look up an indirect /Length when reading a stream.
    using Resolver = std::function<ObjPtr(const Ref&)>;

    Parser(std::string_view data, size_t pos = 0, Resolver resolver = nullptr)
        : lex_(data, pos), resolver_(std::move(resolver)) {}

    // Parse the next object. Keywords become Operator objects. Returns nullptr at end of input.
    ObjPtr parse();

    // Parse "num gen obj <object> endobj" at the current position.
    bool parseIndirect(int& num, int& gen, ObjPtr& out);

    size_t pos() const { return lex_.pos(); }
    void seek(size_t p) { lex_.seek(p); }
    Lexer& lexer() { return lex_; }

private:
    ObjPtr parseFromToken(const Token& t, int depth);
    ObjPtr readStreamBody(ObjPtr dict);
    Lexer lex_;
    Resolver resolver_;
};

}  // namespace anyfile::pdf
