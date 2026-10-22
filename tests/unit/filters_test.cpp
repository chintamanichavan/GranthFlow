#include "pdf/filters.hpp"
#include "check.hpp"

using namespace anyfile::pdf;

TEST(flate_round_trip_and_tolerance) {
    std::string s;   // mildly compressible so a truncated stream still yields a prefix
    for (int i = 0; i < 20000; ++i) s += static_cast<char>('a' + (i * 7919 + i / 13) % 26);
    std::string z = flateEncode(s);
    CHECK(z.size() < s.size());
    CHECK_EQ(flateDecode(z), s);
    CHECK_EQ(flateDecode("\r\n" + z), s);                      // leading whitespace before the header
    std::string partial = flateDecode(z.substr(0, z.size() / 2));
    CHECK(partial.size() > 0 && s.compare(0, partial.size(), partial) == 0);   // truncated: keep the prefix
    CHECK_EQ(flateDecode("not zlib"), "");
}

TEST(ascii_hex) {
    CHECK_EQ(asciiHexDecode("48656C6C6F>"), "Hello");
    CHECK_EQ(asciiHexDecode("48 65\n6c 6C 6f"), "Hello");
    CHECK_EQ(asciiHexDecode("4"), std::string("@"));
}

TEST(ascii85) {
    CHECK_EQ(ascii85Decode("9jqo^F*2M7~>"), "Man sure");
    CHECK_EQ(ascii85Decode("<~9jqo^~>"), "Man ");
    CHECK_EQ(ascii85Decode("9jqo"), "Man");          // partial final group
    CHECK_EQ(ascii85Decode("z~>"), std::string(4, '\0'));
}

TEST(png_predictors) {
    // columns=3, colors=1, bpc=8; each row starts with the filter type byte
    std::string up = std::string("\x02\x01\x02\x03", 4) + std::string("\x02\x01\x01\x01", 4);
    CHECK_EQ(applyPredictor(up, 12, 1, 8, 3), std::string("\x01\x02\x03\x02\x03\x04", 6));
    std::string sub = std::string("\x01\x01\x01\x01", 4);
    CHECK_EQ(applyPredictor(sub, 11, 1, 8, 3), std::string("\x01\x02\x03", 3));
    std::string none = std::string("\x00\x09\x08\x07", 4);
    CHECK_EQ(applyPredictor(none, 10, 1, 8, 3), std::string("\x09\x08\x07", 3));
    std::string avg = std::string("\x03\x02\x02\x02", 4);   // a=left, b=0 above -> +a/2
    CHECK_EQ(applyPredictor(avg, 15, 1, 8, 3), std::string("\x02\x03\x03", 3));
}

TEST(tiff_predictor) {
    CHECK_EQ(applyPredictor(std::string("\x01\x01\x01", 3), 2, 1, 8, 3), std::string("\x01\x02\x03", 3));
    CHECK_EQ(applyPredictor("abc", 1, 1, 8, 3), "abc");   // predictor 1 = none
}

TEST(decode_stream_filter_chain) {
    auto resolve = [](const ObjPtr& o) { return o; };
    std::string z = flateEncode("payload");
    std::string hex;
    for (unsigned char c : z) { char b[3]; std::snprintf(b, 3, "%02X", c); hex += b; }
    ObjPtr s = makeStream({{"Filter", makeArray({makeName("ASCIIHexDecode"), makeName("FlateDecode")})}}, hex + ">");
    FilterResult r = decodeStream(*s, resolve);
    CHECK(r.complete); CHECK_EQ(r.data, "payload");

    ObjPtr single = makeStream({{"Filter", makeName("Fl")}}, z);
    CHECK_EQ(decodeStream(*single, resolve).data, "payload");

    ObjPtr none = makeStream({}, "raw");
    CHECK_EQ(decodeStream(*none, resolve).data, "raw");
}

TEST(decode_stream_reports_unsupported_filter) {
    auto resolve = [](const ObjPtr& o) { return o; };
    ObjPtr s = makeStream({{"Filter", makeName("DCTDecode")}}, "jpeg bytes");
    FilterResult r = decodeStream(*s, resolve);
    CHECK(!r.complete); CHECK_EQ(r.unsupported, "DCTDecode");
}

TEST(decode_stream_applies_predictor_from_parms) {
    auto resolve = [](const ObjPtr& o) { return o; };
    std::string raw = std::string("\x02\x01\x02\x03", 4) + std::string("\x02\x01\x01\x01", 4);
    ObjPtr s = makeStream({{"Filter", makeName("FlateDecode")},
                           {"DecodeParms", makeDict({{"Predictor", makeInt(12)}, {"Columns", makeInt(3)}})}}, flateEncode(raw));
    CHECK_EQ(decodeStream(*s, resolve).data, std::string("\x01\x02\x03\x02\x03\x04", 6));
}
