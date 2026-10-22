#include <sstream>

#include "core/handler.hpp"
#include "check.hpp"
#include "epub_fixture.hpp"
#include "fixtures.hpp"

using namespace anyfile;

struct Run { Status status; std::string out, err; };
static Run run(const std::string& path, const std::string& cmd, std::vector<std::string> args = {}, const std::string& forced = "") {
    std::string kind;
    auto h = makeHandler(path, forced, kind);
    std::ostringstream o, e;
    Status s = h ? h->run(cmd, args, o, e) : Status::Error;
    return {s, o.str(), e.str()};
}
static std::string kindOf(const std::string& path, const std::string& forced = "") { std::string k; makeHandler(path, forced, k); return k; }
static TempDir& dir() { static TempDir t; return t; }

// ---------------------------------------------------------------- detection

TEST(detection_by_magic_extension_and_content) {
    CHECK_EQ(kindOf(dir().file("a.pdf", "%PDF-1.4\n")), "pdf");
    CHECK_EQ(kindOf(dir().file("a.bin", "   %PDF-1.4\n")), "pdf");          // magic beats extension
    CHECK_EQ(kindOf(dir().file("a.md", "# hi")), "markdown");
    CHECK_EQ(kindOf(dir().file("a.MARKDOWN", "# hi")), "markdown");
    CHECK_EQ(kindOf(dir().file("a.txt", "plain")), "text");
    CHECK_EQ(kindOf(dir().file("noext", "plain")), "text");
    CHECK_EQ(kindOf(dir().file("a.dat", std::string("\x00\x01\x02", 3))), "binary");
    CHECK_EQ(kindOf(dir().file("a.txt", "plain"), "binary"), "binary");     // forced
    CHECK_EQ(kindOf(dir().file("a.txt", "plain"), "md"), "markdown");
    CHECK_EQ(kindOf(dir().file("a.epub", epubBytes())), "epub");
    CHECK_EQ(kindOf(dir().file("book.zip", epubBytes())), "epub");              // mimetype entry beats extension
    anyfile::zip::Archive plainZip; plainZip.put("readme.txt", "x");
    CHECK_EQ(kindOf(dir().file("plain.zip", plainZip.serialize())), "binary");  // any other zip stays binary
    CHECK_EQ(kindOf(dir().file("fake.epub", "just text")), "text");             // extension alone is not enough
    std::string k; CHECK(makeHandler(dir().file("a.txt", "x"), "bogus", k) == nullptr);
}

TEST(unknown_command_and_help) {
    std::string p = dir().file("u.txt", "x\n");
    CHECK(run(p, "frobnicate").status == Status::Unknown);
    Run h = run(p, "help");
    CHECK(h.status == Status::Ok);
    CHECK_CONTAINS(h.out, "replace <old> <new>"); CHECK_CONTAINS(h.out, "hex [offset]");
}

// ---------------------------------------------------------------- bytes

TEST(byte_commands) {
    std::string p = dir().file("b.bin", std::string("\x7f" "ELF\x00hello\x00", 10));
    Run i = run(p, "info");
    CHECK_CONTAINS(i.out, "type:       binary"); CHECK_CONTAINS(i.out, "size:       10 B");
    CHECK_CONTAINS(run(p, "hex").out, "7f 45 4c 46 00 68 65 6c");
    CHECK_CONTAINS(run(p, "hex", {"0x5", "5"}).out, "|hello|");
    CHECK(run(p, "hex", {"99"}).status == Status::Error);
    CHECK(run(p, "hex", {"abc"}).status == Status::BadUsage);
    CHECK_CONTAINS(run(p, "strings").out, "0x5: hello");
    CHECK_EQ(run(p, "strings", {"6"}).out, "");
    CHECK(run(p, "patch", {"5", "4a"}).status == Status::Ok);
    CHECK_CONTAINS(run(p, "strings").out, "Jello");   // 0x4a is J
    CHECK(run(p, "patch-str", {"5", "HELLO"}).status == Status::Ok);
    CHECK_CONTAINS(TempDir::read(p), "HELLO");
    CHECK(run(p, "patch", {"5", "zz"}).status == Status::BadUsage);
    CHECK(run(p, "patch", {"50", "00"}).status == Status::Error);
    CHECK(run(p, "patch", {"9", "0102"}).status == Status::Ok);               // grows the file
    CHECK_EQ(TempDir::read(p).size(), size_t(11));
    CHECK(run(p, "append-bytes", {"ff"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p).size(), size_t(12));
    CHECK(run(p, "truncate", {"4"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), std::string("\x7f" "ELF", 4));
    CHECK(run(p, "truncate", {"99"}).status == Status::Error);
}

// ---------------------------------------------------------------- text

TEST(text_read_commands) {
    std::string p = dir().file("t.txt", "alpha\nbeta\ngamma\n");
    CHECK_CONTAINS(run(p, "info").out, "lines:      3");
    CHECK_EQ(run(p, "show").out, "alpha\nbeta\ngamma\n");
    CHECK_EQ(run(p, "show", {"2:3"}).out, "beta\ngamma\n");
    CHECK_EQ(run(p, "show", {"2:"}).out, "beta\ngamma\n");
    CHECK_EQ(run(p, "lines", {":1"}).out, "1\talpha\n");
    CHECK(run(p, "show", {"x"}).status == Status::BadUsage);
    CHECK_EQ(run(p, "grep", {"^b"}).out, "2:beta\n");
    CHECK(run(p, "grep", {"["}).status == Status::BadUsage);
    CHECK_CONTAINS(run(p, "count").out, "words:      3");
}

TEST(text_edit_commands) {
    std::string p = dir().file("e.txt", "alpha\nbeta\ngamma\n");
    CHECK(run(p, "insert", {"2", "x\\ty"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "alpha\nx\ty\nbeta\ngamma\n");
    CHECK(run(p, "set-line", {"2", "two"}).status == Status::Ok);
    CHECK(run(p, "delete", {"2"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "alpha\nbeta\ngamma\n");
    CHECK(run(p, "replace", {"a", "A"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "Alpha\nbeta\ngamma\n");
    CHECK_CONTAINS(run(p, "replace", {"a", "A", "--all"}).out, "replaced 4");
    CHECK(run(p, "replace", {"zzz", "y"}).status == Status::Error);
    CHECK(run(p, "replace", {"", "y"}).status == Status::BadUsage);
    CHECK(run(p, "replace-regex", {"^(\\w)", "[$1]", "--all"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "[A]lphA\n[b]etA\n[g]AmmA\n");
    CHECK(run(p, "append", {"end"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "[A]lphA\n[b]etA\n[g]AmmA\nend\n");
    CHECK(run(p, "delete", {"1:3"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "end\n");
    CHECK(run(p, "insert", {"9", "x"}).status == Status::Error);
    CHECK(run(p, "set-line", {"9", "x"}).status == Status::Error);
    CHECK(run(p, "delete", {"9"}).status == Status::BadUsage);
}

TEST(text_edits_keep_crlf_and_missing_trailing_newline) {
    std::string p = dir().file("crlf.txt", "a\r\nb");
    CHECK(run(p, "set-line", {"1", "A"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "A\r\nb");
    CHECK(run(p, "append", {"c"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "A\r\nb\r\nc\r\n");
}

// ---------------------------------------------------------------- markdown

static const char* kMd = "# Title\n\nIntro [l](http://x) and `code`.\n\n## A\n\nbody a\n\n```\n# not a heading\n```\n\n## B\n\nbody b\n\nSetext\n------\n\nlast\n";

TEST(markdown_structure_commands) {
    std::string p = dir().file("m.md", kMd);
    CHECK_CONTAINS(run(p, "info").out, "headings:   4");
    CHECK_EQ(run(p, "outline").out, "1\tTitle\n5\t  A\n13\t  B\n17\t  Setext\n");
    CHECK_EQ(run(p, "section", {"a"}).out, "## A\n\nbody a\n\n```\n# not a heading\n```\n\n");
    CHECK_EQ(run(p, "section", {"Setext"}).out, "Setext\n------\n\nlast\n");
    Run miss = run(p, "section", {"Nope"});
    CHECK(miss.status == Status::Error); CHECK_CONTAINS(miss.err, "Available:");
    CHECK_EQ(run(p, "links").out, "3\tl\thttp://x\n");
    CHECK_CONTAINS(run(p, "toc").out, "  - [A](#a)\n");
    std::string r = run(p, "render", {"--no-color"}).out;
    CHECK_CONTAINS(r, "# Title"); CHECK_CONTAINS(r, "# not a heading");   // fenced code is printed verbatim
    std::string c = run(p, "render").out;
    CHECK_CONTAINS(c, "\x1b[1m");            // ANSI styling present by default
}

TEST(markdown_edit_commands) {
    std::string p = dir().file("me.md", "# T\n\n## A\n\nold\n\n## B\n\nb\n");
    CHECK(run(p, "replace-section", {"A", "new1\\nnew2"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "# T\n\n## A\n\nnew1\nnew2\n\n## B\n\nb\n");
    CHECK(run(p, "add-section", {"2", "C", "cc"}).status == Status::Ok);
    CHECK_EQ(TempDir::read(p), "# T\n\n## A\n\nnew1\nnew2\n\n## B\n\nb\n\n## C\n\ncc\n");
    CHECK(run(p, "add-section", {"7", "X"}).status == Status::BadUsage);
    CHECK(run(p, "replace-section", {"Zed", "x"}).status == Status::Error);
    CHECK(run(p, "grep", {"new"}).status == Status::Ok);                         // inherited text commands work
    CHECK_CONTAINS(run(p, "hex", {"0", "4"}).out, "|# T.|");                     // and byte commands
}

// ---------------------------------------------------------------- pdf

TEST(pdf_read_commands) {
    std::string p = dir().file("r.pdf", simpleDoc("BT /F1 12 Tf 10 100 Td (Hello) Tj ET").build());
    Run i = run(p, "info");
    CHECK_CONTAINS(i.out, "pdf:        version 1.4, 1 pages, 6 objects, xref table");
    CHECK_CONTAINS(i.out, "Title:      Fixture");
    CHECK_EQ(run(p, "text").out, "Hello\n");
    CHECK_EQ(run(p, "text", {"1"}).out, "Hello\n");
    CHECK(run(p, "text", {"2"}).status == Status::Error);
    CHECK_EQ(run(p, "pages").out, "1\tobj 3\t300 x 200 pt\n");
    CHECK_EQ(run(p, "meta").out, "Author: unit\nTitle: Fixture\n");
    Run o = run(p, "object", {"5"});
    CHECK_CONTAINS(o.out, "5 0 obj"); CHECK_CONTAINS(o.out, "(Hello) Tj");
    CHECK(run(p, "object", {"x"}).status == Status::BadUsage);
    std::string outFile = dir().path + "/text.txt";
    CHECK(run(p, "text", {"--out", outFile}).status == Status::Ok);
    CHECK_EQ(TempDir::read(outFile), "Hello\n");
}

TEST(pdf_modify_commands) {
    std::string p = dir().file("w.pdf", simpleDoc("BT /F1 12 Tf 10 100 Td (Hello World) Tj ET").build());
    CHECK(run(p, "set-meta", {"Title", "New"}).status == Status::Ok);
    CHECK_CONTAINS(run(p, "meta").out, "Title: New");
    CHECK_CONTAINS(run(p, "meta").out, "ModDate: D:");
    CHECK_CONTAINS(run(p, "replace", {"World", "There"}).out, "page 1: 1 replacement");
    CHECK_EQ(run(p, "text").out, "Hello There\n");
    CHECK(run(p, "replace", {"nothing", "x"}).status == Status::Error);
    CHECK_CONTAINS(run(p, "add-page", {"Page two\\nline two"}).out, "added page 2");
    CHECK_EQ(run(p, "text", {"2"}).out, "Page two\nline two\n");
    CHECK_CONTAINS(run(p, "pages").out, "2\tobj");
    CHECK(run(p, "add-note", {"1", "note"}).status == Status::Ok);
    CHECK_CONTAINS(run(p, "object", {"3"}).out, "/Annots");
    CHECK(run(p, "add-note", {"9", "note"}).status == Status::Error);
    std::string copy = dir().path + "/w2.pdf";
    CHECK(run(p, "delete-page", {"2", "--out", copy}).status == Status::Ok);
    CHECK_CONTAINS(run(copy, "info").out, "1 pages");
    CHECK_CONTAINS(run(p, "info").out, "2 pages");                           // original untouched by --out
    CHECK(run(copy, "delete-page", {"1"}).status == Status::Error);           // cannot delete the only page
    CHECK(run(p, "set-meta", {"OnlyKey"}).status == Status::BadUsage);
}

TEST(pdf_modify_refused_when_encrypted) {
    PdfBuilder b = simpleDoc("BT ET");
    b.trailerExtra = " /Encrypt << /Filter /Standard >>";
    std::string p = dir().file("enc.pdf", b.build());
    Run r = run(p, "set-meta", {"Title", "x"});
    CHECK(r.status == Status::Error); CHECK_CONTAINS(r.err, "encrypted");
    CHECK_CONTAINS(run(p, "info").out, "ENCRYPTED");
}

TEST(pdf_unreadable_file_reports_error) {
    std::string p = dir().file("bad.pdf", "%PDF-1.4\ngarbage with no objects");
    Run r = run(p, "text");
    CHECK(r.status == Status::Error); CHECK_CONTAINS(r.err, "error:");
    CHECK_CONTAINS(run(p, "info").out, "pdf:        unreadable");
}

// ---------------------------------------------------------------- epub

TEST(epub_cover_names_the_image_and_cat_returns_its_bytes) {
    zip::Archive a = epubArchive();
    std::string opf, e;
    a.read("OEBPS/content.opf", opf, e);
    opf.replace(opf.find("  </manifest>"), 0, "    <item id=\"c\" href=\"cover.jpg\" media-type=\"image/jpeg\" properties=\"cover-image\"/>\n");
    a.put("OEBPS/content.opf", opf);
    std::string jpeg("\xFF\xD8\xFF\xE0\0\x10JFIF\0", 11);                     // binary, with NUL bytes
    a.put("OEBPS/cover.jpg", jpeg);
    std::string p = dir().file("covered.epub", a.serialize());
    CHECK_EQ(run(p, "cover").out, "OEBPS/cover.jpg\n");
    CHECK(run(p, "cat", {"OEBPS/cover.jpg"}).out == jpeg);                      // stored bytes, untouched
    Run none = run(dir().file("plain.epub", epubBytes()), "cover");
    CHECK(none.status == Status::Error);
    CHECK_CONTAINS(none.err, "no cover image");
}

TEST(epub_read_commands) {
    std::string p = dir().file("r.epub", epubBytes());
    Run i = run(p, "info");
    CHECK_CONTAINS(i.out, "type:       epub");
    CHECK_CONTAINS(i.out, "epub:       version 3.0, 3 chapters, 8 files\n");
    CHECK_CONTAINS(i.out, "Title:      The Test Book"); CHECK_CONTAINS(i.out, "Author:     Ada & Bob");
    CHECK_EQ(run(p, "chapters").out, "1\tOpening\tOEBPS/text/ch1.xhtml\n2\tThe Middle\tOEBPS/text/ch 2.xhtml\n3\tUnlisted Heading\tOEBPS/text/ch3.xhtml\n");
    CHECK_EQ(run(p, "meta").out, "identifier: urn:uuid:1234\ntitle: The Test Book\ncreator: Ada & Bob\nlanguage: en\n");
    CHECK_EQ(run(p, "text", {"3"}).out, "Unlisted Heading\n\nLast words.\n");
    Run all = run(p, "text");
    CHECK(all.status == Status::Ok);
    CHECK_CONTAINS(all.out, "== 1. Opening ==\n\nChapter One\n\nHello brave world.");
    CHECK_CONTAINS(all.out, "== 3. Unlisted Heading ==\n\nUnlisted Heading\n\nLast words.\n");
    CHECK(run(p, "text", {"4"}).status == Status::Error);
    CHECK(run(p, "text", {"0"}).status == Status::BadUsage);
    CHECK(run(p, "text", {"x"}).status == Status::BadUsage);
    Run f = run(p, "files");
    CHECK_CONTAINS(f.out, "20\tmimetype\n"); CHECK_CONTAINS(f.out, "15\tOEBPS/style.css\n");
    CHECK_EQ(run(p, "cat", {"OEBPS/style.css"}).out, "p { margin: 0 }");
    CHECK(run(p, "cat").status == Status::BadUsage);
    CHECK(run(p, "cat", {"missing"}).status == Status::Error);
    CHECK_CONTAINS(run(p, "help").out, "chapters"); CHECK_CONTAINS(run(p, "help").out, "hex [offset]");
    CHECK_CONTAINS(run(p, "hex", {"0", "4"}).out, "50 4b 03 04");            // byte commands still work
}

TEST(epub_set_meta) {
    std::string p = dir().file("m.epub", epubBytes());
    Run r = run(p, "set-meta", {"title", "Renamed"});
    CHECK(r.status == Status::Ok); CHECK_CONTAINS(r.out, "set title = \"Renamed\""); CHECK_CONTAINS(r.out, "saved " + p);
    CHECK_CONTAINS(run(p, "meta").out, "title: Renamed\n");
    CHECK(run(p, "set-meta", {"Author", "Grace"}).status == Status::Ok);
    CHECK_CONTAINS(run(p, "info").out, "Author:     Grace");
    CHECK(run(p, "set-meta", {"publisher", "Home"}).status == Status::Ok);
    CHECK_CONTAINS(run(p, "meta").out, "publisher: Home\n");
    CHECK(run(p, "set-meta", {"title"}).status == Status::BadUsage);
    CHECK(run(p, "set-meta", {"bad key", "x"}).status == Status::BadUsage);
    CHECK_EQ(run(p, "text", {"3"}).out, "Unlisted Heading\n\nLast words.\n");   // chapters untouched
    CHECK_EQ(TempDir::read(p).substr(30, 28), "mimetypeapplication/epub+zip");    // still a valid EPUB header
}

TEST(epub_replace) {
    std::string p = dir().file("w.epub", epubBytes());
    Run first = run(p, "replace", {"alpha", "ALPHA"});
    CHECK(first.status == Status::Ok); CHECK_EQ(first.out, "chapter 2: 1 replacement\nsaved " + p + "\n");
    CHECK_CONTAINS(run(p, "text", {"2"}).out, "- ALPHA\n- beta\n\nalpha again");
    CHECK_CONTAINS(run(p, "replace", {"alpha", "ALPHA", "--all"}).out, "chapter 2: 2 replacements");
    CHECK_CONTAINS(run(p, "replace", {"words", "WORDS", "--all"}).out, "chapter 3: 1 replacement");
    Run none = run(p, "replace", {"absent", "x"});
    CHECK(none.status == Status::Error); CHECK_CONTAINS(none.err, "no match for \"absent\"");
    CHECK(run(p, "replace", {"only"}).status == Status::BadUsage);
}

TEST(epub_replace_chapter_flag_and_out) {
    zip::Archive a = epubArchive();
    a.put("OEBPS/text/ch3.xhtml", xhtmlPage("three", "<p>alpha in three</p>"));
    std::string p = dir().file("c.epub", a.serialize());
    std::string before = TempDir::read(p);
    std::string copy = dir().path + "/c2.epub";
    Run r = run(p, "replace", {"alpha", "X", "--chapter", "3", "--all", "--out", copy});
    CHECK_EQ(r.out, "chapter 3: 1 replacement\nsaved " + copy + "\n");
    CHECK_EQ(TempDir::read(p), before);                                       // original untouched by --out
    CHECK_EQ(run(copy, "text", {"3"}).out, "X in three\n");
    CHECK_CONTAINS(run(copy, "text", {"2"}).out, "- alpha");
    CHECK(run(p, "replace", {"alpha", "X", "--chapter", "9"}).status == Status::Error);
    CHECK(run(p, "replace", {"alpha", "X", "--chapter", "zero"}).status == Status::BadUsage);
    // Without --all only the first chapter that matches is changed.
    CHECK_EQ(run(p, "replace", {"alpha", "X"}).out, "chapter 2: 1 replacement\nsaved " + p + "\n");
    CHECK_EQ(run(p, "text", {"3"}).out, "alpha in three\n");
}

TEST(epub_broken_files_report_errors) {
    std::string bytes = epubBytes();
    std::string cut = dir().file("cut.epub", bytes.substr(0, bytes.size() / 2));
    Run r = run(cut, "text");
    CHECK(r.status == Status::Error); CHECK_CONTAINS(r.err, "error:");
    CHECK_CONTAINS(run(cut, "info").out, "epub:       unreadable");
    CHECK(run(cut, "hex").status == Status::Ok);                              // still inspectable as bytes

    zip::Archive missing = epubArchive();
    missing.put("OEBPS/content.opf", "<package version=\"3.0\"><manifest><item id=\"a\" href=\"gone.xhtml\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"nope\"/></spine></package>");
    std::string p = dir().file("missing.epub", missing.serialize());
    CHECK_EQ(run(p, "chapters").out, "1\tgone.xhtml\tOEBPS/gone.xhtml\n");    // unknown idref dropped, file name as title
    Run t = run(p, "text");
    CHECK(t.status == Status::Error); CHECK_CONTAINS(t.err, "no entry named OEBPS/gone.xhtml");
}
