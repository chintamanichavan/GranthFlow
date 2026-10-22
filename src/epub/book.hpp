// An EPUB as a reader sees it: metadata, an ordered list of chapters, and their text.
// Layout on disk: a zip holding META-INF/container.xml, which names the package file (.opf),
// which lists every file (manifest) and the reading order (spine).
#pragma once
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "zip.hpp"

namespace anyfile::epub {

struct Chapter {
    std::string path;    // name inside the archive
    std::string label;   // from the table of contents; empty when the book lists none for this file
};

// Plain text of one XHTML document: block elements become line breaks, runs of white space
// collapse, entities are decoded. `heading` receives the first h1-h3, else the <title>.
std::string htmlToText(const std::string& xhtml, std::string* heading = nullptr);

// Resolves `href` against the directory of `base`, dropping any #fragment and folding "..".
std::string resolvePath(const std::string& base, const std::string& href);

class Book {
public:
    bool load(std::string bytes, std::string& error);

    const std::string& version() const { return version_; }
    const std::string& packagePath() const { return opfPath_; }
    const std::vector<Chapter>& chapters() const { return chapters_; }
    const std::vector<std::pair<std::string, std::string>>& metadata() const { return metadata_; }   // ("title", "..."), in file order
    std::string meta(const std::string& key) const;                                                  // first value, or ""
    const zip::Archive& archive() const { return zip_; }
    // The cover image's name inside the archive, or "" when the book has none.
    const std::string& coverPath() const { return coverPath_; }

    // `title` receives what chapterTitle() would return, without reading the chapter a second time.
    bool chapterText(size_t index, std::string& out, std::string& error, std::string* title = nullptr) const;
    std::string chapterTitle(size_t index) const;   // contents label, else first heading, else file name

    // Sets (or adds) a Dublin Core entry such as title, creator, language. "author" means creator.
    bool setMeta(const std::string& key, const std::string& value, std::string& error);
    // Replaces literal text inside one chapter's text nodes. Returns the count, or -1 on error.
    // Text split across tags ("Hel<b>lo</b>") is not matched.
    int replaceText(size_t index, const std::string& from, const std::string& to, bool all, std::string& error);

    std::string serialize() const { return zip_.serialize(); }

private:
    void parsePackage();
    void readLabels(const std::string& path, bool ncx, std::map<std::string, std::string>& labels) const;
    bool readChapter(size_t index, std::string& xhtml, std::string& error) const;
    std::string fileName(size_t index) const;

    zip::Archive zip_;
    std::string opfPath_, opf_, version_, coverPath_;
    std::vector<Chapter> chapters_;
    std::vector<std::pair<std::string, std::string>> metadata_;
};

}  // namespace anyfile::epub
