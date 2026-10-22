#include "pdf/lexer.hpp"
#include "check.hpp"

using namespace anyfile::pdf;

static std::vector<Token> all(const std::string& s) {
    Lexer lex(s);
    std::vector<Token> out;
    for (Token t = lex.next(); !t.is(Token::End); t = lex.next()) out.push_back(t);
    return out;
}

TEST(numbers_including_odd_pdf_forms) {
    auto t = all("42 -3.5 .5 --5 +7 6.");
    CHECK_EQ(t.size(), size_t(6));
    CHECK(t[0].is(Token::Number) && t[0].isInteger); CHECK_EQ(t[0].number, 42.0);
    CHECK_EQ(t[1].number, -3.5); CHECK(!t[1].isInteger);
    CHECK_EQ(t[2].number, 0.5);
    CHECK_EQ(t[3].number, 5.0);   // double minus cancels, as real-world files do
    CHECK_EQ(t[4].number, 7.0);
    CHECK_EQ(t[5].number, 6.0); CHECK(!t[5].isInteger);
}

TEST(names_with_hex_escapes) {
    auto t = all("/Name /A#20B /Type/Font /");
    CHECK_EQ(t.size(), size_t(5));
    CHECK(t[0].is(Token::Name)); CHECK_EQ(t[0].text, "Name");
    CHECK_EQ(t[1].text, "A B");
    CHECK_EQ(t[2].text, "Type"); CHECK_EQ(t[3].text, "Font");
    CHECK_EQ(t[4].text, "");
}

TEST(literal_strings_escapes_and_nesting) {
    auto t = all("(a\\)b) (nested (x) y) (\\101\\n\\t) (line\\\ncont) (\\q)");
    CHECK_EQ(t.size(), size_t(5));
    CHECK_EQ(t[0].text, "a)b");
    CHECK_EQ(t[1].text, "nested (x) y");
    CHECK_EQ(t[2].text, "A\n\t");
    CHECK_EQ(t[3].text, "linecont");
    CHECK_EQ(t[4].text, "q");
}

TEST(hex_strings) {
    auto t = all("<48656C6C6F> <41 42> <414>");
    CHECK_EQ(t[0].text, "Hello");
    CHECK_EQ(t[1].text, "AB");
    CHECK_EQ(t[2].text, std::string("A@"));   // odd final digit is padded with 0
}

TEST(delimiters_and_keywords) {
    auto t = all("[ ] << >> { } obj endobj R true");
    CHECK(t[0].is(Token::ArrayOpen)); CHECK(t[1].is(Token::ArrayClose));
    CHECK(t[2].is(Token::DictOpen)); CHECK(t[3].is(Token::DictClose));
    CHECK(t[4].is(Token::BraceOpen)); CHECK(t[5].is(Token::BraceClose));
    CHECK(t[6].isKeyword("obj")); CHECK(t[7].isKeyword("endobj")); CHECK(t[8].isKeyword("R")); CHECK(t[9].isKeyword("true"));
}

TEST(comments_are_skipped) {
    auto t = all("1 % a comment\n2\r%another\r\n3");
    CHECK_EQ(t.size(), size_t(3));
    CHECK_EQ(t[2].number, 3.0);
}

TEST(peek_does_not_consume) {
    Lexer lex("1 2");
    CHECK_EQ(lex.peek().number, 1.0);
    CHECK_EQ(lex.next().number, 1.0);
    CHECK_EQ(lex.next().number, 2.0);
    CHECK(lex.next().is(Token::End));
}

TEST(seek_and_pos) {
    Lexer lex("abc def");
    lex.next();
    size_t p = lex.pos();
    CHECK_EQ(lex.next().text, "def");
    lex.seek(p);
    CHECK_EQ(lex.next().text, "def");
    lex.seek(9999);
    CHECK(lex.atEnd());
}

TEST(unterminated_string_does_not_hang) {
    auto t = all("(never closed");
    CHECK_EQ(t.size(), size_t(1));
    CHECK_EQ(t[0].text, "never closed");
}
