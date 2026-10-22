// Stream filters needed to read text and cross-reference streams.
#pragma once
#include <string>

#include "lexer.hpp"
#include "object.hpp"

namespace anyfile::pdf {

std::string flateDecode(const std::string& in);
std::string asciiHexDecode(const std::string& in);
std::string ascii85Decode(const std::string& in);
std::string flateEncode(const std::string& in);
// PNG/TIFF predictor post-processing for FlateDecode / LZWDecode (used by xref streams).
std::string applyPredictor(const std::string& in, int predictor, int colors, int bitsPerComponent, int columns);

struct FilterResult {
    std::string data;
    bool complete = true;         // false if a filter was unsupported (e.g. DCTDecode image data)
    std::string unsupported;      // name of the first unsupported filter
};

// Apply the /Filter chain of a stream. `resolve` dereferences indirect objects inside /DecodeParms.
FilterResult decodeStream(const Object& stream, const std::function<ObjPtr(const ObjPtr&)>& resolve);

}  // namespace anyfile::pdf
