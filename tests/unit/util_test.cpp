#include "core/util.hpp"
#include "check.hpp"
#include "fixtures.hpp"

using namespace anyfile::util;

TEST(split_and_join_preserve_newline_style) {
    std::string nl;
    auto lf = splitLines("a\nb\nc\n", &nl);
    CHECK_EQ(lf.size(), size_t(3)); CHECK_EQ(nl, "\n");
    CHECK_EQ(joinLines(lf, nl, true), "a\nb\nc\n");
    auto crlf = splitLines("a\r\nb\r\n", &nl);
    CHECK_EQ(crlf.size(), size_t(2)); CHECK_EQ(crlf[0], "a"); CHECK_EQ(nl, "\r\n");
    CHECK_EQ(joinLines(crlf, nl, true), "a\r\nb\r\n");
    auto noTrail = splitLines("a\nb");
    CHECK_EQ(noTrail.size(), size_t(2));
    CHECK_EQ(joinLines(noTrail, "\n", false), "a\nb");
    CHECK_EQ(splitLines("").size(), size_t(0));
}

TEST(paths) {
    CHECK_EQ(lowerExt("/x/y/File.MD"), ".md");
    CHECK_EQ(lowerExt("noext"), "");
    CHECK_EQ(lowerExt("/dir.d/noext"), "");
    CHECK_EQ(baseName("/a/b/c.txt"), "c.txt");
    CHECK_EQ(baseName("c.txt"), "c.txt");
}

TEST(looks_like_text) {
    CHECK(looksLikeText("hello\nworld\t"));
    CHECK(looksLikeText(""));
    CHECK(!looksLikeText(std::string("ab\0cd", 5)));
    CHECK(!looksLikeText("\x01\x02\x03\x04\x05\x06 x"));
    CHECK(looksLikeText("caf\xc3\xa9"));   // UTF-8 is fine
}

TEST(hex_dump_format) {
    std::string d = hexDump("ABC", 0, 0, 16);
    CHECK_CONTAINS(d, "00000000  41 42 43");
    CHECK_CONTAINS(d, "|ABC|");
    CHECK_EQ(hexDump("", 0, 0, 16), "");
    std::string two = hexDump(std::string(20, 'z'), 0, 0, 20);
    CHECK_CONTAINS(two, "00000010  7a 7a 7a 7a");
}

TEST(parse_hex_bytes) {
    std::string out;
    CHECK(parseHexBytes("48656c6c6f", out)); CHECK_EQ(out, "Hello");
    CHECK(parseHexBytes("0x48 65:6C", out)); CHECK_EQ(out, "Hel");
    CHECK(!parseHexBytes("abc", out));
    CHECK(!parseHexBytes("zz", out));
}

TEST(parse_size) {
    size_t v;
    CHECK(parseSize("42", v)); CHECK_EQ(v, size_t(42));
    CHECK(parseSize("0x10", v)); CHECK_EQ(v, size_t(16));
    CHECK(!parseSize("", v)); CHECK(!parseSize("12x", v)); CHECK(!parseSize("-1", v) || v > 1000);
}

TEST(human_size_and_unescape) {
    CHECK_EQ(humanSize(512), "512 B");
    CHECK_CONTAINS(humanSize(2048), "2.0 KiB");
    CHECK_EQ(unescape("a\\nb\\tc\\\\d\\q"), "a\nb\tc\\d\\q");
}

TEST(atomic_write_and_read) {
    TempDir t;
    std::string p = t.path + "/f.txt", err, data;
    CHECK(writeFile(p, "one", err));
    CHECK(readFile(p, data, err)); CHECK_EQ(data, "one");
    CHECK(writeFile(p, "two", err));
    CHECK(readFile(p, data, err)); CHECK_EQ(data, "two");
    CHECK(fileExists(p));
    CHECK(!fileExists(t.path));                        // a directory is not a regular file
    CHECK(!writeFile(t.path + "/missing/dir/f", "x", err)); CHECK(!err.empty());
    CHECK(!readFile(t.path + "/nope", data, err));
    CHECK(!fileExists(p + ".anyfile.tmp"));            // no temp file left behind
}
