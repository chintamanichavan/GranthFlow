#include "epub/zip.hpp"
#include "check.hpp"

using namespace anyfile;

static std::string sample() {
    zip::Archive a;
    a.put("mimetype", "application/epub+zip");
    a.put("a/long.txt", std::string(5000, 'x') + "tail");
    a.put("tiny.txt", "hi");
    return a.serialize();
}

static zip::Archive loaded(const std::string& bytes) {
    zip::Archive a; std::string e;
    CHECK(a.load(bytes, e));
    return a;
}

TEST(round_trip_keeps_names_order_and_content) {
    zip::Archive a = loaded(sample());
    CHECK_EQ(a.entries().size(), size_t(3));
    CHECK_EQ(a.entries()[0].name, "mimetype");
    CHECK_EQ(a.entries()[1].name, "a/long.txt");
    std::string out, e;
    CHECK(a.read("a/long.txt", out, e));
    CHECK_EQ(out, std::string(5000, 'x') + "tail");
    CHECK(a.read("tiny.txt", out, e));
    CHECK_EQ(out, "hi");
    CHECK(a.has("mimetype")); CHECK(!a.has("nope"));
    CHECK(!a.read("nope", out, e));
    CHECK_CONTAINS(e, "no entry named nope");
}

TEST(mimetype_is_stored_first_at_the_fixed_offset) {
    // EPUB readers sniff the type from these exact byte positions.
    std::string z = sample();
    CHECK_EQ(z.substr(0, 4), "PK\x03\x04");
    CHECK_EQ(z.substr(30, 8), "mimetype");
    CHECK_EQ(z.substr(38, 20), "application/epub+zip");
}

TEST(compressible_entries_are_deflated_and_small_ones_stored) {
    zip::Archive a = loaded(sample());
    CHECK_EQ(int(a.entries()[0].method), 0);
    CHECK_EQ(int(a.entries()[1].method), 8);
    CHECK(a.entries()[1].compressedSize < 100);
    CHECK_EQ(a.entries()[1].size, uint32_t(5004));
    CHECK_EQ(int(a.entries()[2].method), 0);     // "hi" would grow if deflated
}

TEST(put_replaces_one_entry_and_leaves_the_rest_byte_identical) {
    std::string before = sample();
    zip::Archive a = loaded(before);
    a.put("tiny.txt", "changed");
    std::string out, e;
    CHECK(a.read("tiny.txt", out, e));           // readable before serializing
    CHECK_EQ(out, "changed");
    std::string after = a.serialize();
    zip::Archive b = loaded(after);
    CHECK_EQ(b.entries().size(), size_t(3));
    CHECK(b.read("tiny.txt", out, e)); CHECK_EQ(out, "changed");
    CHECK(b.read("a/long.txt", out, e)); CHECK_EQ(out.size(), size_t(5004));
    // Everything before the changed entry is untouched.
    size_t prefix = before.find("tiny.txt") - 30;   // start of its 30-byte local header
    CHECK_EQ(after.substr(0, prefix), before.substr(0, prefix));
}

TEST(put_appends_new_names) {
    zip::Archive a = loaded(sample());
    a.put("new.txt", "fresh");
    zip::Archive b = loaded(a.serialize());
    CHECK_EQ(b.entries().size(), size_t(4));
    CHECK_EQ(b.entries()[3].name, "new.txt");
}

TEST(empty_entry_and_empty_archive) {
    zip::Archive a;
    CHECK_EQ(a.serialize().size(), size_t(22));  // just the end record
    a.put("empty", "");
    zip::Archive b = loaded(a.serialize());
    std::string out = "x", e;
    CHECK(b.read("empty", out, e));
    CHECK_EQ(out, "");
}

TEST(trailing_comment_after_end_record_is_tolerated) {
    std::string z = sample();
    z[z.size() - 2] = 5;                          // comment length
    z += "hello";
    zip::Archive a = loaded(z);
    CHECK_EQ(a.entries().size(), size_t(3));
}

TEST(rejects_garbage_and_truncation) {
    zip::Archive a; std::string e;
    CHECK(!a.load("", e)); CHECK_CONTAINS(e, "too short");
    CHECK(!a.load(std::string(100, 'A'), e)); CHECK_CONTAINS(e, "no end record");
    std::string z = sample();
    CHECK(!a.load(z.substr(0, z.size() - 10), e));
    CHECK(!a.load(z.substr(40), e));              // directory offsets now point at the wrong bytes
    CHECK_CONTAINS(e, "corrupt zip");
}

TEST(detects_damaged_data_by_checksum) {
    std::string z = sample();
    z[z.find("tiny.txt") + 8] = 'H';             // first content byte of the stored entry
    zip::Archive a = loaded(z);
    std::string out, e;
    CHECK(!a.read("tiny.txt", out, e));
    CHECK_CONTAINS(e, "checksum mismatch");
}

TEST(detects_damaged_deflate_stream) {
    std::string z = sample();
    size_t p = z.find("a/long.txt") + 10;
    for (size_t i = 0; i < 8; ++i) z[p + i] = '\xFF';
    zip::Archive a = loaded(z);
    std::string out, e;
    CHECK(!a.read("a/long.txt", out, e));
}

TEST(refuses_zip64_encrypted_and_unknown_methods) {
    std::string z = sample();
    std::string z64 = z;
    z64[z64.size() - 12] = z64[z64.size() - 11] = '\xFF';   // entry count 0xFFFF marks Zip64
    zip::Archive a; std::string e, out;
    CHECK(!a.load(z64, e)); CHECK_CONTAINS(e, "Zip64");

    size_t dir = z.rfind("PK\x01\x02");          // last directory record is tiny.txt
    std::string enc = z; enc[dir + 8] = 1;
    zip::Archive b = loaded(enc);
    CHECK(!b.read("tiny.txt", out, e)); CHECK_CONTAINS(e, "encrypted");

    std::string odd = z; odd[dir + 10] = 12;     // bzip2
    zip::Archive c = loaded(odd);
    CHECK(!c.read("tiny.txt", out, e)); CHECK_CONTAINS(e, "unsupported compression method 12");
}

TEST(crc_matches_the_standard_check_value) {
    CHECK_EQ(zip::crc32Of("123456789"), uint32_t(0xCBF43926));
}
