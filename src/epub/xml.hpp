// A forgiving XML/XHTML tokenizer. It reports where each token sits in the source,
// so callers can edit a document by splicing bytes instead of rebuilding it.
#pragma once
#include <string>
#include <utility>
#include <vector>

namespace anyfile::xml {

struct Token {
    enum Kind { Open, Close, Text } kind = Text;
    std::string name;                                          // tag name as written, e.g. "dc:title"
    std::vector<std::pair<std::string, std::string>> attrs;    // values already entity-decoded
    bool selfClosing = false;
    std::string text;                                          // raw source text (entities not decoded)
    bool cdata = false;                                        // text came from <![CDATA[ ]]> and is literal
    size_t begin = 0, end = 0;                                 // byte range in the source
    std::string attr(const std::string& key) const;            // "" when absent
};

class Reader {
public:
    explicit Reader(const std::string& source) : s_(source) {}
    bool next(Token& t);        // false at end of input; comments, doctype and <?...?> are skipped

private:
    const std::string& s_;
    size_t pos_ = 0;
};

std::string decodeEntities(const std::string& s);   // &amp; &#8217; &#x2019; and common named entities
std::string escape(const std::string& s);           // & < > only, for text nodes
std::string localName(const std::string& name);     // "dc:title" -> "title", lower-cased

}  // namespace anyfile::xml
