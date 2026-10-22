#include "epub/xml.hpp"
#include "check.hpp"

using namespace anyfile;

static std::vector<xml::Token> all(const std::string& s) {
    std::vector<xml::Token> ts; xml::Reader r(s); xml::Token t;
    while (r.next(t)) ts.push_back(t);
    return ts;
}

TEST(tags_text_and_attributes) {
    auto ts = all("<a href=\"x.html\" class='k'>hi</a>");
    CHECK_EQ(ts.size(), size_t(3));
    CHECK(ts[0].kind == xml::Token::Open); CHECK_EQ(ts[0].name, "a");
    CHECK_EQ(ts[0].attr("href"), "x.html"); CHECK_EQ(ts[0].attr("class"), "k"); CHECK_EQ(ts[0].attr("none"), "");
    CHECK(ts[1].kind == xml::Token::Text); CHECK_EQ(ts[1].text, "hi");
    CHECK(ts[2].kind == xml::Token::Close); CHECK_EQ(ts[2].name, "a");
}

TEST(self_closing_and_attribute_edge_cases) {
    auto ts = all("<item id=\"a\" href = 'b c.xhtml' /><br/><input disabled value=5>");
    CHECK_EQ(ts.size(), size_t(3));
    CHECK(ts[0].selfClosing); CHECK_EQ(ts[0].attr("href"), "b c.xhtml");
    CHECK(ts[1].selfClosing); CHECK_EQ(ts[1].name, "br");
    CHECK(!ts[2].selfClosing); CHECK_EQ(ts[2].attr("value"), "5"); CHECK_EQ(ts[2].attrs.size(), size_t(2));
}

TEST(attribute_values_are_decoded_and_may_contain_gt) {
    auto ts = all("<a title=\"1 &gt; 0 &amp; x>y\">t</a>");
    CHECK_EQ(ts[0].attr("title"), "1 > 0 & x>y");
    CHECK_EQ(ts[1].text, "t");
}

TEST(offsets_cover_the_source_exactly) {
    std::string s = "<p>one</p><p>two</p>";
    auto ts = all(s);
    CHECK_EQ(ts.size(), size_t(6));
    CHECK_EQ(s.substr(ts[4].begin, ts[4].end - ts[4].begin), "two");
    CHECK_EQ(s.substr(ts[3].begin, ts[3].end - ts[3].begin), "<p>");
    size_t at = 0;
    for (const auto& t : ts) { CHECK_EQ(t.begin, at); at = t.end; }   // no gaps
    CHECK_EQ(at, s.size());
}

TEST(comments_declarations_and_doctype_are_skipped) {
    auto ts = all("<?xml version=\"1.0\"?><!DOCTYPE html [ <!ENTITY x \"y>z\"> ]><!-- <b>no</b> --><p>x</p>");
    CHECK_EQ(ts.size(), size_t(3));
    CHECK_EQ(ts[0].name, "p");
}

TEST(cdata_is_literal_text_with_inner_offsets) {
    std::string s = "<s><![CDATA[a < b && c]]></s>";
    auto ts = all(s);
    CHECK_EQ(ts.size(), size_t(3));
    CHECK(ts[1].cdata); CHECK_EQ(ts[1].text, "a < b && c");
    CHECK_EQ(s.substr(ts[1].begin, ts[1].end - ts[1].begin), "a < b && c");
}

TEST(stray_angle_bracket_stays_text) {
    auto ts = all("<p>a < b</p>");
    CHECK_EQ(ts.size(), size_t(4));
    CHECK_EQ(ts[1].text, "a "); CHECK_EQ(ts[2].text, "< b");
}

TEST(unterminated_input_does_not_hang_or_crash) {
    for (const char* s : {"<p", "<p class=\"x", "<!-- open", "<![CDATA[open", "<?pi", "<!DOCTYPE x [", "text <", "<"}) {
        auto ts = all(s);
        CHECK(ts.size() <= 2);
    }
    CHECK_EQ(all("").size(), size_t(0));
}

TEST(entities_named_numeric_and_unknown) {
    CHECK_EQ(xml::decodeEntities("a &amp; b &lt;c&gt; &quot;q&quot; &apos;"), "a & b <c> \"q\" '");
    CHECK_EQ(xml::decodeEntities("&#65;&#x42;&#x2019;&mdash;&nbsp;"), "AB\xE2\x80\x99\xE2\x80\x94\xC2\xA0");
    CHECK_EQ(xml::decodeEntities("&#128512;"), "\xF0\x9F\x98\x80");
    CHECK_EQ(xml::decodeEntities("AT&T; &bogus; &#xZZ; &; & alone &#0;"), "AT&T; &bogus; &#xZZ; &; & alone &#0;");
}

TEST(escape_round_trips_through_decode) {
    std::string raw = "if a < b && c > d";
    CHECK_EQ(xml::escape(raw), "if a &lt; b &amp;&amp; c &gt; d");
    CHECK_EQ(xml::decodeEntities(xml::escape(raw)), raw);
}

TEST(local_name_strips_prefix_and_case) {
    CHECK_EQ(xml::localName("dc:Title"), "title");
    CHECK_EQ(xml::localName("P"), "p");
    CHECK_EQ(xml::localName("opf:meta"), "meta");
}
