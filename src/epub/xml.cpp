#include "xml.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>

namespace anyfile::xml {

namespace {
bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }
bool startsWith(const std::string& s, size_t p, const char* lit) { return s.compare(p, std::char_traits<char>::length(lit), lit) == 0; }

void appendUtf8(std::string& out, unsigned long cp) {
    if (cp < 0x80) out += static_cast<char>(cp);
    else if (cp < 0x800) { out += static_cast<char>(0xC0 | (cp >> 6)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += static_cast<char>(0xE0 | (cp >> 12)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else { out += static_cast<char>(0xF0 | (cp >> 18)); out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
}

// XML defines five names; the rest are the HTML ones that books actually use.
struct Named { const char* name; unsigned long cp; };
const Named kNamed[] = {
    {"amp", '&'}, {"lt", '<'}, {"gt", '>'}, {"quot", '"'}, {"apos", '\''},
    {"nbsp", 0xA0}, {"copy", 0xA9}, {"reg", 0xAE}, {"shy", 0xAD}, {"deg", 0xB0}, {"middot", 0xB7},
    {"ndash", 0x2013}, {"mdash", 0x2014}, {"lsquo", 0x2018}, {"rsquo", 0x2019}, {"ldquo", 0x201C}, {"rdquo", 0x201D},
    {"hellip", 0x2026}, {"bull", 0x2022}, {"trade", 0x2122}, {"eacute", 0xE9}, {"egrave", 0xE8}, {"agrave", 0xE0},
    {"ccedil", 0xE7}, {"uuml", 0xFC}, {"ouml", 0xF6}, {"auml", 0xE4}, {"ntilde", 0xF1}, {"times", 0xD7},
};
}  // namespace

std::string Token::attr(const std::string& key) const {
    for (const auto& a : attrs) if (a.first == key) return a.second;
    return "";
}

std::string decodeEntities(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size(); ++i) {
        size_t semi = s[i] == '&' ? s.find(';', i) : std::string::npos;
        if (semi == std::string::npos || semi - i > 10 || semi == i + 1) { out += s[i]; continue; }
        std::string ref = s.substr(i + 1, semi - i - 1);
        if (ref[0] == '#') {
            bool hex = ref.size() > 1 && (ref[1] == 'x' || ref[1] == 'X');
            char* stop = nullptr;
            unsigned long cp = std::strtoul(ref.c_str() + (hex ? 2 : 1), &stop, hex ? 16 : 10);
            if (*stop != '\0' || cp == 0 || cp > 0x10FFFF) { out += s[i]; continue; }
            appendUtf8(out, cp);
            i = semi;
            continue;
        }
        const Named* hit = std::find_if(std::begin(kNamed), std::end(kNamed), [&](const Named& n) { return ref == n.name; });
        if (hit == std::end(kNamed)) { out += s[i]; continue; }   // unknown name: keep the text as written
        appendUtf8(out, hit->cp);
        i = semi;
    }
    return out;
}

std::string escape(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c == '&') out += "&amp;";
        else if (c == '<') out += "&lt;";
        else if (c == '>') out += "&gt;";
        else out += c;
    }
    return out;
}

std::string localName(const std::string& name) {
    size_t colon = name.find(':');
    std::string local = colon == std::string::npos ? name : name.substr(colon + 1);
    std::transform(local.begin(), local.end(), local.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return local;
}

bool Reader::next(Token& t) {
    while (pos_ < s_.size()) {
        t = Token{};
        t.begin = pos_;
        char after = pos_ + 1 < s_.size() ? s_[pos_ + 1] : '\0';
        bool markup = s_[pos_] == '<' && (std::isalpha(static_cast<unsigned char>(after)) || after == '/' || after == '!' || after == '?' || after == '_');
        if (!markup) {
            // Text runs to the next '<'. A '<' that does not start markup ("a < b") stays part of the text.
            size_t stop = s_.find('<', pos_ + 1);
            if (stop == std::string::npos) stop = s_.size();
            t.kind = Token::Text;
            t.text = s_.substr(pos_, stop - pos_);
            t.end = pos_ = stop;
            return true;
        }
        if (startsWith(s_, pos_, "<!--")) {
            size_t stop = s_.find("-->", pos_ + 4);
            pos_ = stop == std::string::npos ? s_.size() : stop + 3;
            continue;
        }
        if (startsWith(s_, pos_, "<![CDATA[")) {
            size_t stop = s_.find("]]>", pos_ + 9);
            if (stop == std::string::npos) stop = s_.size();
            t.kind = Token::Text;
            t.cdata = true;
            t.begin = pos_ + 9;
            t.end = stop;
            t.text = s_.substr(t.begin, stop - t.begin);
            pos_ = std::min(s_.size(), stop + 3);
            return true;
        }
        if (after == '?') {
            size_t stop = s_.find("?>", pos_ + 2);
            pos_ = stop == std::string::npos ? s_.size() : stop + 2;
            continue;
        }
        if (after == '!') {
            // A doctype may carry an internal subset in [ ], which can itself contain '>'.
            size_t gt = s_.find('>', pos_), bracket = s_.find('[', pos_);
            if (bracket != std::string::npos && gt != std::string::npos && bracket < gt) {
                size_t close = s_.find("]>", bracket);
                pos_ = close == std::string::npos ? s_.size() : close + 2;
            } else {
                pos_ = gt == std::string::npos ? s_.size() : gt + 1;
            }
            continue;
        }

        size_t p = pos_ + 1;
        t.kind = Token::Open;
        if (s_[p] == '/') { t.kind = Token::Close; ++p; }
        size_t nameStart = p;
        while (p < s_.size() && !isSpace(s_[p]) && s_[p] != '>' && s_[p] != '/') ++p;
        t.name = s_.substr(nameStart, p - nameStart);
        while (p < s_.size() && s_[p] != '>') {
            if (isSpace(s_[p])) { ++p; continue; }
            if (s_[p] == '/') { t.selfClosing = true; ++p; continue; }
            size_t keyStart = p;
            while (p < s_.size() && !isSpace(s_[p]) && s_[p] != '=' && s_[p] != '>' && s_[p] != '/') ++p;
            std::string key = s_.substr(keyStart, p - keyStart), value;
            while (p < s_.size() && isSpace(s_[p])) ++p;
            if (p < s_.size() && s_[p] == '=') {
                ++p;
                while (p < s_.size() && isSpace(s_[p])) ++p;
                if (p < s_.size() && (s_[p] == '"' || s_[p] == '\'')) {
                    size_t close = s_.find(s_[p], p + 1);
                    if (close == std::string::npos) close = s_.size();
                    value = s_.substr(p + 1, close - p - 1);
                    p = std::min(s_.size(), close + 1);
                } else {
                    size_t valueStart = p;   // unquoted, as sloppy HTML allows
                    while (p < s_.size() && !isSpace(s_[p]) && s_[p] != '>') ++p;
                    value = s_.substr(valueStart, p - valueStart);
                }
            }
            if (!key.empty()) t.attrs.emplace_back(key, decodeEntities(value));
        }
        t.end = pos_ = std::min(s_.size(), p + 1);
        return true;
    }
    return false;
}

}  // namespace anyfile::xml
