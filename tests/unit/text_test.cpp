#include "pdf/text.hpp"
#include "pdf/filters.hpp"
#include "check.hpp"
#include "fixtures.hpp"

using namespace anyfile::pdf;

static std::string textOf(const PdfBuilder& b, ExtractStats* stats = nullptr) {
    TempDir t; Document d; std::string e;
    if (!d.load(t.file("t.pdf", b.build()), e)) { std::printf("  load error: %s\n", e.c_str()); return "<load failed>"; }
    auto pages = d.pages();
    if (pages.empty()) return "<no pages>";
    return extractPageText(d, pages[0], stats);
}

TEST(tj_and_tj_array_spacing) {
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 10 100 Td (Hello) Tj ET")), "Hello\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf [(Hel) 20 (lo) -300 (World)] TJ ET")), "Hello World\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf [(a) -50 (b)] TJ ET")), "ab\n");   // small kerning is not a space
}

TEST(line_breaks_from_text_positioning) {
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 10 100 Td (one) Tj 0 -14 Td (two) Tj ET")), "one\ntwo\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 14 TL 10 100 Td (one) Tj T* (two) Tj ET")), "one\ntwo\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 14 TL 10 100 Td (one) Tj (two) ' ET")), "one\ntwo\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 1 0 0 1 10 100 Tm (one) Tj 1 0 0 1 10 50 Tm (two) Tj ET")), "one\ntwo\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 10 100 Td (a) Tj 40 0 Td (b) Tj ET")), "a b\n");   // same line, gap -> space
}

TEST(multiple_text_objects_and_blank_lines_collapse) {
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 10 100 Td (a) Tj ET BT 10 10 Td (b) Tj ET")), "a\nb\n");
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf 10 100 Td T* T* T* (a) Tj ET")), "a\n");
}

TEST(winansi_and_macroman_high_bytes) {
    std::string win = textOf(simpleDoc("BT /F1 12 Tf (\\223q\\224 \\226 caf\\351) Tj ET",
                                       "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"));
    CHECK_EQ(win, "\xE2\x80\x9Cq\xE2\x80\x9D \xE2\x80\x93 caf\xC3\xA9\n");
    std::string mac = textOf(simpleDoc("BT /F1 12 Tf (\\245 caf\\216) Tj ET",
                                       "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /MacRomanEncoding >>"));
    CHECK_EQ(mac, "\xE2\x80\xA2 caf\xC3\xA9\n");
}

TEST(tounicode_cmap_two_byte_font) {
    std::string cmap = "1 begincodespacerange <0000> <FFFF> endcodespacerange\n"
                       "1 beginbfrange <0001> <0003> <0041> endbfrange\n"
                       "1 beginbfchar <0010> <00E9> endbfchar\n"
                       "1 beginbfrange <0020> <0021> [<0058> <0059>] endbfrange\n";
    PdfBuilder b = simpleDoc("BT /F1 12 Tf <000100020003 0010 0020 0021> Tj ET",
                             "<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H /ToUnicode 7 0 R >>");
    b.objs.push_back({7, streamObj("", cmap)});
    ExtractStats st;
    CHECK_EQ(textOf(b, &st), "ABC\xC3\xA9XY\n");
    CHECK_EQ(st.unmappedGlyphs, 0);
}

TEST(unmapped_cid_glyphs_are_counted_not_guessed) {
    PdfBuilder b = simpleDoc("BT /F1 12 Tf <00010002> Tj ET", "<< /Type /Font /Subtype /Type0 /BaseFont /X /Encoding /Identity-H >>");
    ExtractStats st;
    CHECK_EQ(textOf(b, &st), "");
    CHECK_EQ(st.unmappedGlyphs, 2);
}

TEST(font_decoder_direct) {
    FontDecoder fd;
    CHECK_EQ(fd.decode("abc", nullptr), "abc");
    fd.codeBytes = 2; fd.hasToUnicode = true; fd.toUnicode[0x0041] = "Z";
    ExtractStats st;
    CHECK_EQ(fd.decode(std::string("\x00\x41\x00\x42", 4), &st), "Z");
    CHECK_EQ(st.unmappedGlyphs, 1);
}

TEST(form_xobject_is_followed) {
    PdfBuilder b = simpleDoc("BT /F1 12 Tf 10 100 Td (outer) Tj ET /Fx Do", "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
                             "/Resources << /Font << /F1 4 0 R >> /XObject << /Fx 7 0 R >> >> ");
    b.objs[2].second = "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> /XObject << /Fx 7 0 R >> >> /Contents 5 0 R >>";
    b.objs.push_back({7, streamObj("/Type /XObject /Subtype /Form /BBox [0 0 10 10]", "BT /F1 12 Tf 10 10 Td (inner) Tj ET")});
    CHECK_EQ(textOf(b), "outer\ninner\n");
}

TEST(inline_images_are_skipped) {
    CHECK_EQ(textOf(simpleDoc("BT /F1 12 Tf (a) Tj ET BI /W 1 /H 1 ID \x01\xff(junk) Tj EI BT (b) Tj ET")), "a\nb\n");
}

TEST(contents_array_is_concatenated) {
    PdfBuilder b = simpleDoc("x");
    b.objs[2].second = "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents [5 0 R 7 0 R] >>";
    b.objs[4].second = streamObj("", "BT /F1 12 Tf 10 100 Td (first) Tj");
    b.objs.push_back({7, streamObj("", "0 -20 Td (second) Tj ET")});
    CHECK_EQ(textOf(b), "first\nsecond\n");
}

TEST(replace_text_on_page) {
    TempDir t; Document d; std::string e;
    std::string p = t.file("r.pdf", simpleDoc("BT /F1 12 Tf (Hello World) Tj (Hello again) Tj ET").build());
    CHECK(d.load(p, e));
    auto pages = d.pages();
    CHECK_EQ(replaceTextOnPage(d, pages[0], "Hello", "Bye", false), 1);
    CHECK_EQ(extractPageText(d, pages[0]), "Bye WorldHello again\n");
    CHECK_EQ(replaceTextOnPage(d, pages[0], "Hello", "Bye", true), 1);
    CHECK_EQ(extractPageText(d, pages[0]), "Bye WorldBye again\n");
    CHECK_EQ(replaceTextOnPage(d, pages[0], "missing", "x", true), 0);
    std::string out = t.path + "/r2.pdf";
    CHECK(d.save(out, e));
    Document d2;
    CHECK(d2.load(out, e));
    CHECK_EQ(extractPageText(d2, d2.pages()[0]), "Bye WorldBye again\n");
    CHECK(d2.object(5)->get("Filter")->isName("FlateDecode"));   // rewritten stream is compressed
}

TEST(replace_escapes_special_characters) {
    TempDir t; Document d; std::string e;
    CHECK(d.load(t.file("r.pdf", simpleDoc("BT /F1 12 Tf (abc) Tj ET").build()), e));
    auto pages = d.pages();
    CHECK_EQ(replaceTextOnPage(d, pages[0], "b", ")(\\", false), 1);
    CHECK_EQ(extractPageText(d, pages[0]), "a)(\\c\n");
}
