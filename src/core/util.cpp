#include "util.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

namespace anyfile::util {

bool readFile(const std::string& path, std::string& out, std::string& error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { error = "cannot open " + path; return false; }
    std::ostringstream ss;
    ss << in.rdbuf();
    out = ss.str();
    return true;
}

bool writeFile(const std::string& path, const std::string& data, std::string& error) {
    // Write to a temp file in the same directory, then rename, so a crash never truncates the original.
    std::string tmp = path + ".anyfile.tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) { error = "cannot write " + tmp; return false; }
        out.write(data.data(), static_cast<std::streamsize>(data.size()));
        if (!out) { error = "write failed for " + tmp; std::remove(tmp.c_str()); return false; }
    }
    if (std::rename(tmp.c_str(), path.c_str()) != 0) { error = "cannot replace " + path; std::remove(tmp.c_str()); return false; }
    return true;
}

bool fileExists(const std::string& path) {
    struct stat st{};
    return stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

std::string lowerExt(const std::string& path) {
    size_t slash = path.find_last_of('/');
    size_t dot = path.find_last_of('.');
    if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) return "";
    std::string ext = path.substr(dot);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return ext;
}

std::string baseName(const std::string& path) {
    size_t slash = path.find_last_of('/');
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

bool looksLikeText(const std::string& s) {
    if (s.empty()) return true;
    size_t control = 0;
    for (size_t i = 0; i < s.size(); ++i) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == 0) return false;
        if (c < 0x20 && c != '\n' && c != '\r' && c != '\t' && c != '\f' && c != 0x1B) ++control;
    }
    return control * 50 < s.size();   // under 2% stray control bytes
}

std::vector<std::string> splitLines(const std::string& s, std::string* newline) {
    std::vector<std::string> lines;
    std::string nl = s.find("\r\n") != std::string::npos ? "\r\n" : "\n";
    if (newline) *newline = nl;
    size_t i = 0;
    while (i <= s.size()) {
        size_t e = s.find('\n', i);
        if (e == std::string::npos) {
            if (i < s.size()) lines.push_back(s.substr(i));
            break;
        }
        std::string line = s.substr(i, e - i);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(line);
        i = e + 1;
    }
    return lines;
}

std::string joinLines(const std::vector<std::string>& lines, const std::string& newline, bool trailingNewline) {
    std::string out;
    for (size_t i = 0; i < lines.size(); ++i) {
        out += lines[i];
        if (i + 1 < lines.size() || trailingNewline) out += newline;
    }
    return out;
}

std::string hexDump(const std::string& data, size_t baseOffset, size_t offset, size_t length) {
    std::string out;
    size_t end = std::min(data.size(), offset + length);
    char buf[16];
    for (size_t row = offset; row < end; row += 16) {
        std::snprintf(buf, sizeof buf, "%08zx  ", baseOffset + row);
        out += buf;
        for (size_t i = 0; i < 16; ++i) {
            if (row + i < end) { std::snprintf(buf, sizeof buf, "%02x ", static_cast<unsigned char>(data[row + i])); out += buf; }
            else out += "   ";
            if (i == 7) out += ' ';
        }
        out += " |";
        for (size_t i = 0; i < 16 && row + i < end; ++i) {
            unsigned char c = static_cast<unsigned char>(data[row + i]);
            out += (c >= 32 && c < 127) ? static_cast<char>(c) : '.';
        }
        out += "|\n";
    }
    return out;
}

bool parseHexBytes(const std::string& hexIn, std::string& out) {
    std::string hex;
    for (char c : hexIn) if (!std::isspace(static_cast<unsigned char>(c)) && c != ':') hex += c;
    if (hex.rfind("0x", 0) == 0 || hex.rfind("0X", 0) == 0) hex = hex.substr(2);
    if (hex.size() % 2 != 0) return false;
    out.clear();
    for (size_t i = 0; i < hex.size(); i += 2) {
        auto v = [](char c) { return std::isdigit(static_cast<unsigned char>(c)) ? c - '0' : std::isxdigit(static_cast<unsigned char>(c)) ? (std::tolower(c) - 'a' + 10) : -1; };
        int a = v(hex[i]), b = v(hex[i + 1]);
        if (a < 0 || b < 0) return false;
        out += static_cast<char>(a * 16 + b);
    }
    return true;
}

bool parseSize(const std::string& s, size_t& out) {
    if (s.empty()) return false;
    try {
        size_t idx = 0;
        unsigned long long v = std::stoull(s, &idx, (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) ? 16 : 10);
        if (idx != s.size()) return false;
        out = static_cast<size_t>(v);
        return true;
    } catch (...) { return false; }
}

std::string humanSize(size_t bytes) {
    const char* units[] = {"B", "KiB", "MiB", "GiB"};
    double v = static_cast<double>(bytes);
    int u = 0;
    while (v >= 1024 && u < 3) { v /= 1024; ++u; }
    char buf[32];
    if (u == 0) std::snprintf(buf, sizeof buf, "%zu B", bytes);
    else std::snprintf(buf, sizeof buf, "%.1f %s (%zu bytes)", v, units[u], bytes);
    return buf;
}

std::string unescape(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size()) {
            char e = s[++i];
            switch (e) {
                case 'n': out += '\n'; break;
                case 't': out += '\t'; break;
                case 'r': out += '\r'; break;
                case '\\': out += '\\'; break;
                default: out += '\\'; out += e;
            }
        } else {
            out += s[i];
        }
    }
    return out;
}

}  // namespace anyfile::util
