// Text extraction and in-place text replacement for PDF pages.
#pragma once
#include <map>
#include <string>

#include "document.hpp"

namespace anyfile::pdf {

struct ExtractStats {
    int unmappedGlyphs = 0;      // codes with no ToUnicode mapping (CID fonts without a map)
    int unsupportedStreams = 0;  // content streams using filters we don't decode
};

// Decodes bytes shown by Tj/TJ for one font.
struct FontDecoder {
    int codeBytes = 1;
    bool hasToUnicode = false;
    std::map<int, std::string> toUnicode;    // code -> UTF-8
    std::string encoding;                    // WinAnsiEncoding, MacRomanEncoding, ...
    std::string decode(const std::string& bytes, ExtractStats* stats) const;
};

FontDecoder buildFontDecoder(Document& doc, const ObjPtr& fontDict);
std::string extractPageText(Document& doc, const PageInfo& page, ExtractStats* stats = nullptr);

// Replace literal text in a page's content streams. Only matches strings that appear
// verbatim inside a single Tj/TJ string operand of a simple (1-byte) font. Returns count.
int replaceTextOnPage(Document& doc, const PageInfo& page, const std::string& from, const std::string& to, bool all);

}  // namespace anyfile::pdf
