#include "epub/book.hpp"
#include "check.hpp"
#include "epub_fixture.hpp"

using namespace anyfile;

static epub::Book book(const std::string& version = "3.0") {
    epub::Book b; std::string e;
    CHECK(b.load(epubBytes(version), e));
    return b;
}

// ---------------------------------------------------------------- html to text

TEST(text_blocks_become_lines_and_space_collapses) {
    CHECK_EQ(epub::htmlToText("<body><h1>Title</h1><p>one   two\n three</p><p>four</p></body>"), "Title\n\none two three\n\nfour\n");
    CHECK_EQ(epub::htmlToText("<body><p>a<br/>b</p><div>c</div><div>d</div></body>"), "a\nb\n\nc\nd\n");
}

TEST(text_inline_tags_do_not_break_words) {
    CHECK_EQ(epub::htmlToText("<body><p>Hel<b>lo</b> <i>wor</i>ld</p></body>"), "Hello world\n");
}

TEST(text_skips_head_script_and_style) {
    std::string h = "<html><head><title>T</title><style>p{}</style></head><body><script>var x = '<p>no</p>';</script><p>yes</p><style>.a{}</style></body></html>";
    CHECK_EQ(epub::htmlToText(h), "yes\n");
}

TEST(text_lists_get_bullets_even_with_nested_paragraphs) {
    CHECK_EQ(epub::htmlToText("<body><ul><li>one</li><li><p>two</p></li></ul><p>after</p></body>"), "- one\n- two\n\nafter\n");
}

TEST(text_entities_cdata_pre_and_image_alt) {
    CHECK_EQ(epub::htmlToText("<body><p>a &amp; b &#8212; c<![CDATA[ <raw> ]]></p></body>"), "a & b \xE2\x80\x94 c <raw>\n");
    CHECK_EQ(epub::htmlToText("<body><pre>x\n   y</pre></body>"), "x\n   y\n");
    CHECK_EQ(epub::htmlToText("<body><p>see <img src=\"a.png\" alt=\"a map\"/> here</p></body>"), "see [a map] here\n");
}

TEST(text_fragment_without_body_and_empty_input) {
    CHECK_EQ(epub::htmlToText("<p>bare</p>"), "bare\n");
    CHECK_EQ(epub::htmlToText(""), "");
    CHECK_EQ(epub::htmlToText("<html><body></body></html>"), "");
}

TEST(heading_is_first_h1_to_h3_else_title) {
    std::string h;
    epub::htmlToText("<html><head><title>Doc</title></head><body><p>x</p><h2>The <em>Real</em>\n One</h2><h1>Later</h1></body></html>", &h);
    CHECK_EQ(h, "The Real One");
    epub::htmlToText("<html><head><title> Doc  Title </title></head><body><p>x</p></body></html>", &h);
    CHECK_EQ(h, "Doc Title");
    epub::htmlToText("<p>x</p>", &h);
    CHECK_EQ(h, "");
}

// ---------------------------------------------------------------- paths

TEST(resolve_path_joins_decodes_and_folds) {
    CHECK_EQ(epub::resolvePath("OEBPS/content.opf", "text/ch1.xhtml"), "OEBPS/text/ch1.xhtml");
    CHECK_EQ(epub::resolvePath("OEBPS/content.opf", "text/ch%202.xhtml#frag"), "OEBPS/text/ch 2.xhtml");
    CHECK_EQ(epub::resolvePath("OEBPS/text/nav.xhtml", "../img/./a.png"), "OEBPS/img/a.png");
    CHECK_EQ(epub::resolvePath("content.opf", "ch1.xhtml"), "ch1.xhtml");
    CHECK_EQ(epub::resolvePath("a/b.opf", "../../../x"), "x");              // cannot climb out of the archive
    CHECK_EQ(epub::resolvePath("a/b.opf", "/root.xhtml"), "root.xhtml");
    CHECK_EQ(epub::resolvePath("a/b.opf", "100%.txt"), "a/100%.txt");        // a bare % is not an escape
}

// ---------------------------------------------------------------- book

TEST(load_reads_version_metadata_and_spine) {
    epub::Book b = book();
    CHECK_EQ(b.version(), "3.0");
    CHECK_EQ(b.packagePath(), "OEBPS/content.opf");
    CHECK_EQ(b.meta("title"), "The Test Book");
    CHECK_EQ(b.meta("creator"), "Ada & Bob");
    CHECK_EQ(b.meta("language"), "en");
    CHECK_EQ(b.meta("publisher"), "");
    CHECK_EQ(b.metadata().size(), size_t(4));          // the <meta> element is not Dublin Core
    CHECK_EQ(b.chapters().size(), size_t(3));           // css and nav are in the manifest but not the spine
    CHECK_EQ(b.chapters()[1].path, "OEBPS/text/ch 2.xhtml");
}

TEST(chapter_titles_from_nav_then_heading) {
    epub::Book b = book();
    CHECK_EQ(b.chapterTitle(0), "Opening");
    CHECK_EQ(b.chapterTitle(1), "The Middle");          // first link to the file wins
    CHECK_EQ(b.chapterTitle(2), "Unlisted Heading");
    CHECK_EQ(b.chapterTitle(9), "");
}

TEST(chapter_titles_from_ncx_in_epub2) {
    epub::Book b = book("2.0");
    CHECK_EQ(b.version(), "2.0");
    CHECK_EQ(b.chapterTitle(0), "Opening");
    CHECK_EQ(b.chapterTitle(1), "The Middle");
    CHECK_EQ(b.chapterTitle(2), "Unlisted Heading");
}

TEST(chapter_text) {
    epub::Book b = book();
    std::string t, e;
    CHECK(b.chapterText(0, t, e));
    CHECK_EQ(t, "Chapter One\n\nHello brave world.\n\nIt\xE2\x80\x99s a <test> & more.\n");
    CHECK(b.chapterText(1, t, e));
    CHECK_EQ(t, "Second\n\n- alpha\n- beta\n\nalpha again, alpha twice\n");
    CHECK(!b.chapterText(3, t, e));
    CHECK_CONTAINS(e, "no chapter 4 (book has 3)");
    std::string title;
    CHECK(b.chapterText(0, t, e, &title)); CHECK_EQ(title, "Opening");            // same answers as chapterTitle()
    CHECK(b.chapterText(2, t, e, &title)); CHECK_EQ(title, "Unlisted Heading");
}

TEST(load_rejects_non_epub_zip_and_missing_package) {
    epub::Book b; std::string e;
    zip::Archive plain; plain.put("a.txt", "x");
    CHECK(!b.load(plain.serialize(), e)); CHECK_CONTAINS(e, "not an EPUB");
    zip::Archive noRoot; noRoot.put("META-INF/container.xml", "<container/>");
    CHECK(!b.load(noRoot.serialize(), e)); CHECK_CONTAINS(e, "names no package file");
    zip::Archive noOpf; noOpf.put("META-INF/container.xml", "<rootfile full-path=\"gone.opf\"/>");
    CHECK(!b.load(noOpf.serialize(), e)); CHECK_CONTAINS(e, "no entry named gone.opf");
    CHECK(!b.load("not a zip at all, just some text here", e));
}

TEST(missing_chapter_file_and_utf16_are_reported) {
    zip::Archive a = epubArchive();
    a.put("OEBPS/text/ch1.xhtml", std::string("\xFF\xFE<\0p\0>\0", 8));
    epub::Book b; std::string e, t;
    CHECK(b.load(a.serialize(), e));
    CHECK(!b.chapterText(0, t, e)); CHECK_CONTAINS(e, "UTF-16");
    CHECK_EQ(b.chapterTitle(0), "Opening");             // label still comes from the contents
}

// ---------------------------------------------------------------- editing

TEST(set_meta_replaces_existing_value_and_survives_reload) {
    epub::Book b = book();
    std::string e;
    CHECK(b.setMeta("Title", "New <Name> & Co", e));
    CHECK_EQ(b.meta("title"), "New <Name> & Co");
    epub::Book again; CHECK(again.load(b.serialize(), e));
    CHECK_EQ(again.meta("title"), "New <Name> & Co");
    CHECK_EQ(again.meta("creator"), "Ada & Bob");       // neighbours untouched
    CHECK_EQ(again.chapters().size(), size_t(3));
}

TEST(set_meta_author_is_creator_and_new_keys_are_added) {
    epub::Book b = book();
    std::string e;
    CHECK(b.setMeta("author", "Grace", e));
    CHECK_EQ(b.meta("creator"), "Grace");
    CHECK(b.setMeta("publisher", "Home Press", e));
    epub::Book again; CHECK(again.load(b.serialize(), e));
    CHECK_EQ(again.meta("publisher"), "Home Press");
    CHECK_EQ(again.metadata().size(), size_t(5));
}

TEST(set_meta_rejects_bad_keys) {
    epub::Book b = book();
    std::string e;
    CHECK(!b.setMeta("", "x", e));
    CHECK(!b.setMeta("ti tle", "x", e));
    CHECK(!b.setMeta("a><b", "x", e));
    CHECK_CONTAINS(e, "metadata key must be a word");
}

TEST(replace_first_and_all) {
    epub::Book b = book();
    std::string e, t;
    CHECK_EQ(b.replaceText(1, "alpha", "ALPHA", false, e), 1);
    CHECK(b.chapterText(1, t, e));
    CHECK_EQ(t, "Second\n\n- ALPHA\n- beta\n\nalpha again, alpha twice\n");
    CHECK_EQ(b.replaceText(1, "alpha", "ALPHA", true, e), 2);
    CHECK(b.chapterText(1, t, e));
    CHECK_CONTAINS(t, "ALPHA again, ALPHA twice");
    CHECK_EQ(b.replaceText(1, "nowhere", "x", true, e), 0);
}

TEST(replace_matches_decoded_text_and_escapes_the_result) {
    epub::Book b = book();
    std::string e, t;
    CHECK_EQ(b.replaceText(0, "It\xE2\x80\x99s a <test> & more", "1 < 2 & 3", false, e), 1);
    CHECK(b.chapterText(0, t, e));
    CHECK_CONTAINS(t, "1 < 2 & 3.");
    std::string raw;
    CHECK(b.archive().read("OEBPS/text/ch1.xhtml", raw, e));
    CHECK_CONTAINS(raw, "<p>1 &lt; 2 &amp; 3.</p>");     // still well-formed
    CHECK_CONTAINS(raw, "<h1>Chapter <em>One</em></h1>");  // markup elsewhere untouched
}

TEST(replace_leaves_markup_head_and_style_alone) {
    epub::Book b = book();
    std::string e, raw;
    CHECK_EQ(b.replaceText(0, "margin", "X", true, e), 0);   // only in <style>
    CHECK_EQ(b.replaceText(0, "one", "X", true, e), 0);      // only in <title>; body has "One"
    CHECK_EQ(b.replaceText(0, "em", "X", true, e), 0);       // a tag name, not text
    CHECK_EQ(b.replaceText(0, "Chapter One", "X", true, e), 0);   // split by <em>: documented limit
}

TEST(replace_does_not_loop_when_new_text_contains_old) {
    epub::Book b = book();
    std::string e, t;
    CHECK_EQ(b.replaceText(1, "alpha", "alpha alpha", true, e), 3);
    CHECK(b.chapterText(1, t, e));
    CHECK_CONTAINS(t, "- alpha alpha\n");
}

TEST(replace_errors) {
    epub::Book b = book();
    std::string e;
    CHECK_EQ(b.replaceText(0, "", "x", true, e), -1);
    CHECK_EQ(b.replaceText(7, "a", "x", true, e), -1);
}

TEST(edits_survive_serialize_and_other_entries_stay_identical) {
    epub::Book b = book();
    std::string e, t, css;
    CHECK_EQ(b.replaceText(2, "Last", "Final", false, e), 1);
    epub::Book again; CHECK(again.load(b.serialize(), e));
    CHECK(again.chapterText(2, t, e));
    CHECK_EQ(t, "Unlisted Heading\n\nFinal words.\n");
    CHECK(again.chapterText(0, t, e));
    CHECK_CONTAINS(t, "Hello brave world.");
    CHECK(again.archive().read("OEBPS/style.css", css, e));
    CHECK_EQ(css, "p { margin: 0 }");
    CHECK_EQ(again.archive().entries()[0].name, "mimetype");
}
