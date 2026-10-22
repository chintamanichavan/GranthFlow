// Chooses a handler from the file's magic bytes and extension.
#include <fstream>

#include "handler.hpp"
#include "util.hpp"
#include "../handlers/epub_handler.hpp"
#include "../handlers/markdown_handler.hpp"
#include "../handlers/pdf_handler.hpp"
#include "../handlers/text_handler.hpp"

namespace anyfile {

std::unique_ptr<FileHandler> makeHandler(const std::string& path, const std::string& forced, std::string& detected) {
    std::string kind = forced;
    if (kind.empty()) {
        std::string head;
        {
            std::ifstream in(path, std::ios::binary);
            char buf[8192];
            in.read(buf, sizeof buf);
            head.assign(buf, static_cast<size_t>(in.gcount()));
        }
        std::string ext = util::lowerExt(path);
        size_t pdfHeader = head.find("%PDF-");
        // An EPUB is a zip whose first entry is an uncompressed file named "mimetype" holding the type.
        bool zip = head.compare(0, 4, "PK\x03\x04") == 0;
        bool epubMime = head.size() >= 58 && head.compare(30, 8, "mimetype") == 0 && head.compare(38, 20, "application/epub+zip") == 0;
        if (pdfHeader != std::string::npos && pdfHeader < 1024) kind = "pdf";
        else if (zip && (epubMime || ext == ".epub")) kind = "epub";
        else if (ext == ".md" || ext == ".markdown" || ext == ".mdown" || ext == ".mkd") kind = "markdown";
        else if (util::looksLikeText(head)) kind = "text";
        else kind = "binary";
    }
    detected = kind;
    if (kind == "pdf") return std::make_unique<PdfHandler>(path);
    if (kind == "epub") return std::make_unique<EpubHandler>(path);
    if (kind == "markdown" || kind == "md") { detected = "markdown"; return std::make_unique<MarkdownHandler>(path); }
    if (kind == "text" || kind == "txt") { detected = "text"; return std::make_unique<TextHandler>(path); }
    if (kind == "binary" || kind == "bin" || kind == "hex") { detected = "binary"; return std::make_unique<ByteHandler>(path); }
    return nullptr;
}

}  // namespace anyfile
