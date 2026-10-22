#include "zip.hpp"

#include <zlib.h>

namespace anyfile::zip {

namespace {
const uint32_t kLocal = 0x04034b50, kCentral = 0x02014b50, kEnd = 0x06054b50;
const size_t kLocalSize = 30, kCentralSize = 46, kEndSize = 22;
// A declared size is not proof of anything; refuse entries that would need this much memory.
const uint32_t kMaxEntry = 512u << 20;

uint16_t u16(const std::string& s, size_t p) {
    return static_cast<uint16_t>(static_cast<unsigned char>(s[p]) | (static_cast<unsigned char>(s[p + 1]) << 8));
}
uint32_t u32(const std::string& s, size_t p) { return u16(s, p) | (static_cast<uint32_t>(u16(s, p + 2)) << 16); }
void put16(std::string& s, uint16_t v) { s += static_cast<char>(v & 0xFF); s += static_cast<char>(v >> 8); }
void put32(std::string& s, uint32_t v) { put16(s, static_cast<uint16_t>(v & 0xFFFF)); put16(s, static_cast<uint16_t>(v >> 16)); }

// EPUB uses raw deflate: no zlib header, hence the negative window bits.
bool inflateRaw(const char* in, size_t inSize, uint32_t outSize, std::string& out) {
    out.assign(static_cast<size_t>(outSize) + 1, '\0');   // one spare byte so over-long data is detected
    z_stream z{};
    if (inflateInit2(&z, -MAX_WBITS) != Z_OK) return false;
    z.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(in));
    z.avail_in = static_cast<uInt>(inSize);
    z.next_out = reinterpret_cast<Bytef*>(out.data());
    z.avail_out = static_cast<uInt>(out.size());
    int rc = inflate(&z, Z_FINISH);
    size_t produced = z.total_out;
    inflateEnd(&z);
    if (rc != Z_STREAM_END || produced != outSize) return false;
    out.resize(outSize);
    return true;
}

std::string deflateRaw(const std::string& in) {
    z_stream z{};
    if (deflateInit2(&z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) return "";
    std::string out(deflateBound(&z, static_cast<uLong>(in.size())), '\0');
    z.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(in.data()));
    z.avail_in = static_cast<uInt>(in.size());
    z.next_out = reinterpret_cast<Bytef*>(out.data());
    z.avail_out = static_cast<uInt>(out.size());
    int rc = deflate(&z, Z_FINISH);
    out.resize(rc == Z_STREAM_END ? z.total_out : 0);
    deflateEnd(&z);
    return out;
}
}  // namespace

uint32_t crc32Of(const std::string& s) {
    return static_cast<uint32_t>(crc32(0L, reinterpret_cast<const Bytef*>(s.data()), static_cast<uInt>(s.size())));
}

bool Archive::load(std::string bytes, std::string& error) {
    data_ = std::move(bytes);
    entries_.clear();
    if (data_.size() < kEndSize) { error = "not a zip archive (too short)"; return false; }

    // The end record is last in the file, followed only by a comment of at most 65535 bytes.
    size_t stop = data_.size() > kEndSize + 65535 ? data_.size() - kEndSize - 65535 : 0;
    size_t end = std::string::npos;
    for (size_t p = data_.size() - kEndSize + 1; p-- > stop;) {
        if (u32(data_, p) == kEnd) { end = p; break; }
    }
    if (end == std::string::npos) { error = "not a zip archive (no end record)"; return false; }

    size_t count = u16(data_, end + 10);
    size_t dirSize = u32(data_, end + 12), dirOffset = u32(data_, end + 16);
    if (count == 0xFFFF || dirOffset == 0xFFFFFFFF) { error = "Zip64 archives are not supported"; return false; }
    if (dirOffset + dirSize > data_.size()) { error = "corrupt zip: directory lies outside the file"; return false; }

    size_t p = dirOffset;
    for (size_t i = 0; i < count; ++i) {
        if (p + kCentralSize > data_.size() || u32(data_, p) != kCentral) { error = "corrupt zip: bad directory entry"; return false; }
        Entry e;
        e.flags = u16(data_, p + 8);
        e.method = u16(data_, p + 10);
        e.time = u16(data_, p + 12);
        e.date = u16(data_, p + 14);
        e.crc = u32(data_, p + 16);
        e.compressedSize = u32(data_, p + 20);
        e.size = u32(data_, p + 24);
        size_t nameLen = u16(data_, p + 28), extraLen = u16(data_, p + 30), commentLen = u16(data_, p + 32);
        size_t local = u32(data_, p + 42);
        if (p + kCentralSize + nameLen > data_.size()) { error = "corrupt zip: truncated name"; return false; }
        e.name = data_.substr(p + kCentralSize, nameLen);
        p += kCentralSize + nameLen + extraLen + commentLen;

        // The local header repeats the name and has its own extra field, so its length must be read there.
        if (local + kLocalSize > data_.size() || u32(data_, local) != kLocal) { error = "corrupt zip: bad local header for " + e.name; return false; }
        e.dataOffset = local + kLocalSize + u16(data_, local + 26) + u16(data_, local + 28);
        if (e.dataOffset + e.compressedSize > data_.size()) { error = "corrupt zip: data of " + e.name + " lies outside the file"; return false; }
        entries_.push_back(std::move(e));
    }
    return true;
}

const Entry* Archive::find(const std::string& name) const {
    for (const auto& e : entries_) if (e.name == name) return &e;
    return nullptr;
}

bool Archive::read(const std::string& name, std::string& out, std::string& error) const {
    const Entry* e = find(name);
    if (!e) { error = "no entry named " + name; return false; }
    if (e->fresh) { out = e->content; return true; }
    if (e->flags & 1) { error = name + " is encrypted"; return false; }
    if (e->size > kMaxEntry) { error = name + " is too large to read"; return false; }
    if (e->method == 0) {
        out = data_.substr(e->dataOffset, e->compressedSize);
    } else if (e->method == 8) {
        if (!inflateRaw(data_.data() + e->dataOffset, e->compressedSize, e->size, out)) { error = "cannot decompress " + name; return false; }
    } else {
        error = name + " uses unsupported compression method " + std::to_string(e->method);
        return false;
    }
    if (crc32Of(out) != e->crc) { error = "checksum mismatch in " + name; return false; }
    return true;
}

void Archive::put(const std::string& name, const std::string& content) {
    Entry* e = const_cast<Entry*>(find(name));
    if (!e) { entries_.emplace_back(); e = &entries_.back(); e->name = name; e->flags = 0x0800; }   // new names are UTF-8
    e->fresh = true;
    e->content = content;
}

std::string Archive::serialize() const {
    std::string out, directory;
    for (const Entry& e : entries_) {
        std::string packed;
        uint16_t method = e.method;
        uint32_t crc = e.crc, size = e.size;
        if (e.fresh) {
            crc = crc32Of(e.content);
            size = static_cast<uint32_t>(e.content.size());
            // EPUB requires the mimetype entry to be stored; anything else is deflated when that is smaller.
            packed = e.name == "mimetype" ? "" : deflateRaw(e.content);
            method = (!packed.empty() && packed.size() < e.content.size()) ? 8 : 0;
            if (method == 0) packed = e.content;
        } else {
            packed = data_.substr(e.dataOffset, e.compressedSize);
        }
        // Sizes are written up front, so the "sizes follow the data" bit (3) must not survive.
        uint16_t flags = e.flags & 0x0801;
        uint16_t version = method == 8 ? 20 : 10;
        uint32_t offset = static_cast<uint32_t>(out.size());

        auto fields = [&](std::string& s) {
            put16(s, version); put16(s, flags); put16(s, method); put16(s, e.time); put16(s, e.date);
            put32(s, crc); put32(s, static_cast<uint32_t>(packed.size())); put32(s, size);
            put16(s, static_cast<uint16_t>(e.name.size())); put16(s, 0);
        };
        put32(out, kLocal); fields(out);
        out += e.name; out += packed;

        put32(directory, kCentral); put16(directory, 20); fields(directory);
        put16(directory, 0); put16(directory, 0); put16(directory, 0); put32(directory, 0);   // comment, disk, attributes
        put32(directory, offset);
        directory += e.name;
    }
    uint32_t dirOffset = static_cast<uint32_t>(out.size());
    out += directory;
    put32(out, kEnd); put16(out, 0); put16(out, 0);
    put16(out, static_cast<uint16_t>(entries_.size())); put16(out, static_cast<uint16_t>(entries_.size()));
    put32(out, static_cast<uint32_t>(directory.size())); put32(out, dirOffset); put16(out, 0);
    return out;
}

}  // namespace anyfile::zip
