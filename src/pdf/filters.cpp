#include "filters.hpp"

#include <zlib.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <vector>

namespace anyfile::pdf {

std::string flateDecode(const std::string& input) {
    // Some writers leave stray whitespace before the zlib header; skip it.
    size_t start = 0;
    while (start < input.size() && isWhite(input[start])) ++start;
    if (start >= input.size()) return {};

    z_stream zs{};
    if (inflateInit(&zs) != Z_OK) return {};
    zs.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(input.data() + start));
    zs.avail_in = static_cast<uInt>(input.size() - start);
    std::string out;
    char buf[1 << 16];
    int ret = Z_OK;
    while (ret == Z_OK) {
        zs.next_out = reinterpret_cast<Bytef*>(buf);
        zs.avail_out = sizeof buf;
        ret = inflate(&zs, Z_NO_FLUSH);
        out.append(buf, sizeof buf - zs.avail_out);
        if (ret == Z_BUF_ERROR && zs.avail_in == 0) break;
    }
    inflateEnd(&zs);
    // Z_DATA_ERROR after partial output: keep what we recovered (common with truncated streams).
    return out;
}

std::string flateEncode(const std::string& in) {
    uLongf cap = compressBound(static_cast<uLong>(in.size()));
    std::string out(cap, '\0');
    if (compress2(reinterpret_cast<Bytef*>(out.data()), &cap,
                  reinterpret_cast<const Bytef*>(in.data()), static_cast<uLong>(in.size()), 9) != Z_OK) return {};
    out.resize(cap);
    return out;
}

std::string asciiHexDecode(const std::string& in) {
    std::string out;
    int hi = -1;
    for (char c : in) {
        if (c == '>') break;
        int v = -1;
        if (c >= '0' && c <= '9') v = c - '0';
        else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;
        if (v < 0) continue;
        if (hi < 0) hi = v; else { out += static_cast<char>(hi * 16 + v); hi = -1; }
    }
    if (hi >= 0) out += static_cast<char>(hi * 16);
    return out;
}

std::string ascii85Decode(const std::string& in) {
    std::string out;
    uint32_t tuple = 0;
    int count = 0;
    size_t i = 0;
    if (in.compare(0, 2, "<~") == 0) i = 2;
    for (; i < in.size(); ++i) {
        char c = in[i];
        if (isWhite(c)) continue;
        if (c == '~') break;
        if (c == 'z' && count == 0) { out.append(4, '\0'); continue; }
        if (c < '!' || c > 'u') continue;
        tuple = tuple * 85 + static_cast<uint32_t>(c - '!');
        if (++count == 5) {
            for (int k = 3; k >= 0; --k) out += static_cast<char>((tuple >> (k * 8)) & 0xFF);
            tuple = 0; count = 0;
        }
    }
    if (count > 0) {
        for (int k = count; k < 5; ++k) tuple = tuple * 85 + 84;
        for (int k = 3; k >= 5 - count; --k) out += static_cast<char>((tuple >> (k * 8)) & 0xFF);
    }
    return out;
}

std::string applyPredictor(const std::string& in, int predictor, int colors, int bpc, int columns) {
    if (predictor <= 1) return in;
    int bpp = std::max(1, colors * bpc / 8);
    size_t rowLen = (static_cast<size_t>(columns) * colors * bpc + 7) / 8;
    if (rowLen == 0) return in;

    if (predictor == 2) {  // TIFF predictor, 8-bit only
        if (bpc != 8) return in;
        std::string out = in;
        for (size_t r = 0; r + rowLen <= out.size(); r += rowLen)
            for (size_t i = bpp; i < rowLen; ++i) out[r + i] = static_cast<char>(out[r + i] + out[r + i - bpp]);
        return out;
    }

    std::string out;
    std::vector<unsigned char> prev(rowLen, 0), cur(rowLen, 0);
    size_t pos = 0;
    while (pos < in.size()) {
        int ft = static_cast<unsigned char>(in[pos++]);
        size_t n = std::min(rowLen, in.size() - pos);
        if (n == 0) break;
        std::fill(cur.begin(), cur.end(), 0);
        std::memcpy(cur.data(), in.data() + pos, n);
        pos += n;
        for (size_t i = 0; i < rowLen; ++i) {
            unsigned char a = i >= static_cast<size_t>(bpp) ? cur[i - bpp] : 0;
            unsigned char b = prev[i];
            unsigned char c = i >= static_cast<size_t>(bpp) ? prev[i - bpp] : 0;
            switch (ft) {
                case 1: cur[i] = static_cast<unsigned char>(cur[i] + a); break;
                case 2: cur[i] = static_cast<unsigned char>(cur[i] + b); break;
                case 3: cur[i] = static_cast<unsigned char>(cur[i] + (a + b) / 2); break;
                case 4: {
                    int p = a + b - c;
                    int pa = std::abs(p - a), pb = std::abs(p - b), pc = std::abs(p - c);
                    cur[i] = static_cast<unsigned char>(cur[i] + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)));
                    break;
                }
                default: break;
            }
        }
        out.append(reinterpret_cast<const char*>(cur.data()), rowLen);
        prev = cur;
    }
    return out;
}

FilterResult decodeStream(const Object& stream, const std::function<ObjPtr(const ObjPtr&)>& resolve) {
    FilterResult result;
    result.data = stream.raw;

    std::vector<ObjPtr> filters, params;
    ObjPtr f = resolve(stream.get("Filter"));
    ObjPtr p = resolve(stream.get("DecodeParms"));
    if (p->isNull()) p = resolve(stream.get("DP"));
    if (f->isName()) { filters.push_back(f); params.push_back(p); }
    else if (f->isArray()) {
        for (size_t i = 0; i < f->array.size(); ++i) {
            filters.push_back(resolve(f->array[i]));
            params.push_back(p->isArray() && i < p->array.size() ? resolve(p->array[i]) : (p->isArray() ? makeNull() : p));
        }
    }

    for (size_t i = 0; i < filters.size(); ++i) {
        const std::string& name = filters[i]->str;
        ObjPtr parm = params[i];
        if (name == "FlateDecode" || name == "Fl") {
            result.data = flateDecode(result.data);
        } else if (name == "ASCIIHexDecode" || name == "AHx") {
            result.data = asciiHexDecode(result.data);
        } else if (name == "ASCII85Decode" || name == "A85") {
            result.data = ascii85Decode(result.data);
        } else {
            result.complete = false;
            result.unsupported = name;
            break;
        }
        if (parm->isDict()) {
            int pred = resolve(parm->get("Predictor"))->intValue(1);
            if (pred > 1) {
                result.data = applyPredictor(result.data, pred,
                                             resolve(parm->get("Colors"))->intValue(1),
                                             resolve(parm->get("BitsPerComponent"))->intValue(8),
                                             resolve(parm->get("Columns"))->intValue(1));
            }
        }
    }
    return result;
}

}  // namespace anyfile::pdf
