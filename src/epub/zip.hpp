// Just enough ZIP to read and rewrite an EPUB: stored and deflated entries, no Zip64, no encryption.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace anyfile::zip {

struct Entry {
    std::string name;
    uint16_t method = 0;          // 0 stored, 8 deflate
    uint32_t crc = 0;
    uint32_t compressedSize = 0;
    uint32_t size = 0;
    // Bookkeeping for Archive; callers only need the fields above.
    uint16_t flags = 0, time = 0, date = 0x0021;   // 0x0021 is 1980-01-01, the earliest DOS date
    size_t dataOffset = 0;        // where the compressed bytes start in the loaded archive
    bool fresh = false;           // content was set with put() and is not in the loaded archive
    std::string content;
};

class Archive {
public:
    bool load(std::string bytes, std::string& error);
    const std::vector<Entry>& entries() const { return entries_; }
    bool has(const std::string& name) const { return find(name) != nullptr; }
    bool read(const std::string& name, std::string& out, std::string& error) const;
    void put(const std::string& name, const std::string& content);   // add, or replace in place
    // Untouched entries are copied byte for byte, so only what put() changed is recompressed.
    std::string serialize() const;

private:
    const Entry* find(const std::string& name) const;
    std::string data_;
    std::vector<Entry> entries_;
};

uint32_t crc32Of(const std::string& s);

}  // namespace anyfile::zip
