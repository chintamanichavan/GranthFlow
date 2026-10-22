// A three-chapter book built in memory. Chapters 1 and 2 are named by the contents file, chapter 3 only by its heading.
#pragma once
#include <string>

#include "epub/zip.hpp"

inline std::string xhtmlPage(const std::string& title, const std::string& body) {
    return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<!DOCTYPE html>\n"
           "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>" + title + "</title>"
           "<style>p { margin: 0 }</style></head>\n<body>\n" + body + "\n</body></html>\n";
}

// version "3.0" gets a navigation document, "2.0" an NCX.
inline anyfile::zip::Archive epubArchive(const std::string& version = "3.0") {
    bool three = version == "3.0";
    anyfile::zip::Archive a;
    a.put("mimetype", "application/epub+zip");
    a.put("META-INF/container.xml",
          "<?xml version=\"1.0\"?>\n<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\n"
          "  <rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles>\n</container>\n");
    a.put("OEBPS/content.opf",
          "<?xml version=\"1.0\"?>\n<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"" + version + "\" unique-identifier=\"id\">\n"
          "  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n"
          "    <dc:identifier id=\"id\">urn:uuid:1234</dc:identifier>\n"
          "    <dc:title>The Test Book</dc:title>\n"
          "    <dc:creator>Ada &amp; Bob</dc:creator>\n"
          "    <dc:language>en</dc:language>\n"
          "    <meta property=\"dcterms:modified\">2020-01-01T00:00:00Z</meta>\n"
          "  </metadata>\n"
          "  <manifest>\n"
          "    <item id=\"c1\" href=\"text/ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
          "    <item id=\"c2\" href=\"text/ch%202.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
          "    <item id=\"c3\" href=\"text/ch3.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
          "    <item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>\n" +
          (three ? "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n"
                 : "    <item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>\n") +
          "  </manifest>\n"
          "  <spine" + (three ? "" : " toc=\"ncx\"") + ">\n"
          "    <itemref idref=\"c1\"/><itemref idref=\"c2\"/><itemref idref=\"c3\"/>\n"
          "  </spine>\n</package>\n");
    a.put("OEBPS/text/ch1.xhtml", xhtmlPage("one", "<h1>Chapter <em>One</em></h1>\n<p>Hello   brave\n  world.</p>\n<p>It&#8217;s a &lt;test&gt; &amp; more.</p>"));
    a.put("OEBPS/text/ch 2.xhtml", xhtmlPage("two", "<h2>Second</h2><ul><li>alpha</li><li><p>beta</p></li></ul><p>alpha again, alpha twice</p>"));
    a.put("OEBPS/text/ch3.xhtml", xhtmlPage("three", "<h1>Unlisted Heading</h1><p>Last words.</p>"));
    a.put("OEBPS/style.css", "p { margin: 0 }");
    if (three) {
        a.put("OEBPS/nav.xhtml", xhtmlPage("Contents",
              "<nav epub:type=\"toc\"><ol><li><a href=\"text/ch1.xhtml\">Opening</a></li>"
              "<li><a href=\"text/ch%202.xhtml#top\">The  Middle</a></li><li><a href=\"text/ch%202.xhtml#later\">Later part</a></li></ol></nav>"));
    } else {
        a.put("OEBPS/toc.ncx",
              "<?xml version=\"1.0\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\"><docTitle><text>The Test Book</text></docTitle><navMap>"
              "<navPoint id=\"n1\"><navLabel><text>Opening</text></navLabel><content src=\"text/ch1.xhtml\"/></navPoint>"
              "<navPoint id=\"n2\"><navLabel><text>The Middle</text></navLabel><content src=\"text/ch%202.xhtml\"/></navPoint>"
              "</navMap></ncx>");
    }
    return a;
}

inline std::string epubBytes(const std::string& version = "3.0") { return epubArchive(version).serialize(); }
