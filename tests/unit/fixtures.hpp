// Temp files and PDF builders shared by the unit tests.
#pragma once
#include <unistd.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

struct TempDir {
    std::string path;
    TempDir() { char t[] = "/tmp/anyfile_unit_XXXXXX"; path = mkdtemp(t); }
    ~TempDir() { std::filesystem::remove_all(path); }
    std::string file(const std::string& name, const std::string& content) const {
        std::string p = path + "/" + name;
        std::ofstream(p, std::ios::binary) << content;
        return p;
    }
    static std::string read(const std::string& p) {
        std::ifstream in(p, std::ios::binary);
        std::ostringstream ss; ss << in.rdbuf(); return ss.str();
    }
};

// Builds a classic-xref PDF from numbered object bodies. Offsets can be made wrong on purpose.
struct PdfBuilder {
    std::vector<std::pair<int, std::string>> objs;
    std::string trailerExtra;
    std::string header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";

    std::string build(bool correctOffsets = true, bool withXref = true) const {
        std::string out = header;
        std::map<int, size_t> off;
        int maxNum = 0;
        for (const auto& [n, body] : objs) {
            off[n] = out.size();
            out += std::to_string(n) + " 0 obj\n" + body + "\nendobj\n";
            if (n > maxNum) maxNum = n;
        }
        if (!withXref) return out;
        size_t xref = out.size();
        out += "xref\n0 " + std::to_string(maxNum + 1) + "\n0000000000 65535 f \n";
        for (int i = 1; i <= maxNum; ++i) {
            char buf[32];
            size_t o = off.count(i) ? off[i] : 0;
            if (!correctOffsets && o) o += 7;
            std::snprintf(buf, sizeof buf, "%010zu 00000 %c \n", o, off.count(i) ? 'n' : 'f');
            out += buf;
        }
        out += "trailer\n<< /Size " + std::to_string(maxNum + 1) + " /Root 1 0 R" + trailerExtra + " >>\nstartxref\n" + std::to_string(xref) + "\n%%EOF\n";
        return out;
    }
};

inline std::string streamObj(const std::string& dictEntries, const std::string& data) {
    return "<< " + dictEntries + " /Length " + std::to_string(data.size()) + " >>\nstream\n" + data + "\nendstream";
}

// One page, Helvetica as /F1, the given content stream, and an Info dict.
inline PdfBuilder simpleDoc(const std::string& content,
                            const std::string& fontObj = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
                            const std::string& extraPageEntries = "") {
    PdfBuilder b;
    b.objs = {
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2, "<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 300 200] >>"},
        {3, "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R " + extraPageEntries + ">>"},
        {4, fontObj},
        {5, streamObj("", content)},
        {6, "<< /Title (Fixture) /Author (unit) >>"},
    };
    b.trailerExtra = " /Info 6 0 R";
    return b;
}

// PDF 1.5 style: objects 1-4 live in an object stream, cross-reference is a stream (no filters).
inline std::string xrefStreamDoc(const std::string& content) {
    std::vector<std::pair<int, std::string>> inner = {
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"},
        {3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R >>"},
        {4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"},
    };
    std::string hdr, body;
    for (const auto& [n, o] : inner) { hdr += std::to_string(n) + " " + std::to_string(body.size()) + " "; body += o + "\n"; }
    std::string data = hdr + body;
    std::string out = "%PDF-1.5\n";
    std::map<int, size_t> off;
    auto add = [&](int num, const std::string& s) { off[num] = out.size(); out += std::to_string(num) + " 0 obj\n" + s + "\nendobj\n"; };
    add(5, "<< /Type /ObjStm /N 4 /First " + std::to_string(hdr.size()) + " /Length " + std::to_string(data.size()) + " >>\nstream\n" + data + "\nendstream");
    add(6, streamObj("", content));
    auto row = [](int t, long long f2, int f3) {
        std::string r; r += static_cast<char>(t);
        for (int k = 3; k >= 0; --k) r += static_cast<char>((f2 >> (8 * k)) & 0xFF);
        r += static_cast<char>((f3 >> 8) & 0xFF); r += static_cast<char>(f3 & 0xFF); return r;
    };
    size_t xoff = out.size();
    std::string rows = row(0, 0, 65535);
    for (int i = 0; i < 4; ++i) rows += row(2, 5, i);
    rows += row(1, static_cast<long long>(off[5]), 0) + row(1, static_cast<long long>(off[6]), 0) + row(1, static_cast<long long>(xoff), 0);
    out += "7 0 obj\n<< /Type /XRef /Size 8 /W [1 4 2] /Root 1 0 R /Length " + std::to_string(rows.size()) + " >>\nstream\n" + rows + "\nendstream\nendobj\n";
    out += "startxref\n" + std::to_string(xoff) + "\n%%EOF\n";
    return out;
}
