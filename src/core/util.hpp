#pragma once
#include <string>
#include <vector>

namespace anyfile::util {

bool readFile(const std::string& path, std::string& out, std::string& error);
bool writeFile(const std::string& path, const std::string& data, std::string& error);
bool fileExists(const std::string& path);
std::string lowerExt(const std::string& path);       // ".md", ".pdf", "" ...
std::string baseName(const std::string& path);
bool looksLikeText(const std::string& sample);        // heuristic: UTF-8 / printable, no NULs
std::vector<std::string> splitLines(const std::string& s, std::string* newline = nullptr);
std::string joinLines(const std::vector<std::string>& lines, const std::string& newline, bool trailingNewline);
std::string hexDump(const std::string& data, size_t baseOffset, size_t offset, size_t length);
bool parseHexBytes(const std::string& hex, std::string& out);
bool parseSize(const std::string& s, size_t& out);      // decimal or 0x-prefixed
std::string humanSize(size_t bytes);
std::string unescape(const std::string& s);             // "\n" "\t" "\\" in CLI arguments

}  // namespace anyfile::util
