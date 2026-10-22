#include <algorithm>
#include <sstream>

#include "../core/handler.hpp"
#include "../core/util.hpp"

namespace anyfile {

std::vector<Command> commonCommands() {
    return {
        {"info", "", "Summarize the file: size, detected type, type-specific details"},
        {"hex", "[offset] [length]", "Hex dump (default: first 256 bytes; offsets may be 0x-prefixed)"},
        {"strings", "[min-length]", "Print printable ASCII runs (default length 4)"},
        {"patch", "<offset> <hexbytes>", "Overwrite bytes at offset, e.g. patch 0x10 48656c6c6f"},
        {"patch-str", "<offset> <text>", "Overwrite bytes at offset with the UTF-8 bytes of text"},
        {"truncate", "<length>", "Cut the file to the given length"},
        {"append-bytes", "<hexbytes>", "Append raw bytes to the end of the file"},
        {"help", "", "List commands available for this file"},
    };
}

std::vector<Command> ByteHandler::commands() const { return {}; }

bool ByteHandler::load(std::ostream& err) {
    if (loaded_) return true;
    std::string e;
    if (!util::readFile(path_, data_, e)) { err << "error: " << e << "\n"; return false; }
    loaded_ = true;
    return true;
}

bool ByteHandler::store(std::ostream& err) {
    std::string e;
    if (!util::writeFile(path_, data_, e)) { err << "error: " << e << "\n"; return false; }
    return true;
}

void ByteHandler::describe(std::ostream& out) {
    size_t printable = 0;
    for (unsigned char c : data_) if ((c >= 32 && c < 127) || c == '\n' || c == '\t' || c == '\r') ++printable;
    out << "printable:  " << (data_.empty() ? 0 : printable * 100 / data_.size()) << "%\n";
    if (data_.size() >= 4) out << "magic:      " << util::hexDump(data_.substr(0, std::min<size_t>(16, data_.size())), 0, 0, 16);
}

Status ByteHandler::run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) {
    if (cmd == "help") {
        out << "Commands for " << path_ << " (" << kind() << "):\n";
        auto print = [&](const std::vector<Command>& cs) {
            for (const auto& c : cs) {
                std::string head = c.name + " " + c.usage;
                out << "  " << head << std::string(head.size() < 34 ? 34 - head.size() : 1, ' ') << c.help << "\n";
            }
        };
        print(commands());
        print(commonCommands());
        return Status::Ok;
    }
    if (!load(err)) return Status::Error;

    if (cmd == "info") {
        out << "file:       " << path_ << "\n";
        out << "type:       " << kind() << "\n";
        out << "size:       " << util::humanSize(data_.size()) << "\n";
        describe(out);
        return Status::Ok;
    }
    if (cmd == "hex") {
        size_t off = 0, len = 256;
        if (args.size() >= 1 && !util::parseSize(args[0], off)) { err << "error: bad offset\n"; return Status::BadUsage; }
        if (args.size() >= 2 && !util::parseSize(args[1], len)) { err << "error: bad length\n"; return Status::BadUsage; }
        if (off > data_.size()) { err << "error: offset beyond end of file (" << data_.size() << " bytes)\n"; return Status::Error; }
        out << util::hexDump(data_, 0, off, len);
        return Status::Ok;
    }
    if (cmd == "strings") {
        size_t min = 4;
        if (!args.empty() && !util::parseSize(args[0], min)) { err << "error: bad length\n"; return Status::BadUsage; }
        std::string run;
        size_t start = 0;
        for (size_t i = 0; i <= data_.size(); ++i) {
            unsigned char c = i < data_.size() ? static_cast<unsigned char>(data_[i]) : 0;
            if (c >= 32 && c < 127) { if (run.empty()) start = i; run += static_cast<char>(c); }
            else { if (run.size() >= min) out << "0x" << std::hex << start << std::dec << ": " << run << "\n"; run.clear(); }
        }
        return Status::Ok;
    }
    if (cmd == "patch" || cmd == "patch-str") {
        if (args.size() < 2) { err << "usage: " << cmd << " <offset> <" << (cmd == "patch" ? "hexbytes" : "text") << ">\n"; return Status::BadUsage; }
        size_t off;
        if (!util::parseSize(args[0], off)) { err << "error: bad offset\n"; return Status::BadUsage; }
        std::string bytes;
        if (cmd == "patch") { if (!util::parseHexBytes(args[1], bytes)) { err << "error: bad hex\n"; return Status::BadUsage; } }
        else bytes = util::unescape(args[1]);
        if (off > data_.size()) { err << "error: offset beyond end of file\n"; return Status::Error; }
        if (off + bytes.size() > data_.size()) data_.resize(off + bytes.size());
        std::copy(bytes.begin(), bytes.end(), data_.begin() + static_cast<long>(off));
        if (!store(err)) return Status::Error;
        out << "patched " << bytes.size() << " bytes at offset " << off << "\n";
        return Status::Ok;
    }
    if (cmd == "truncate") {
        size_t len;
        if (args.empty() || !util::parseSize(args[0], len)) { err << "usage: truncate <length>\n"; return Status::BadUsage; }
        if (len > data_.size()) { err << "error: length exceeds file size\n"; return Status::Error; }
        data_.resize(len);
        if (!store(err)) return Status::Error;
        out << "truncated to " << len << " bytes\n";
        return Status::Ok;
    }
    if (cmd == "append-bytes") {
        std::string bytes;
        if (args.empty() || !util::parseHexBytes(args[0], bytes)) { err << "usage: append-bytes <hexbytes>\n"; return Status::BadUsage; }
        data_ += bytes;
        if (!store(err)) return Status::Error;
        out << "appended " << bytes.size() << " bytes\n";
        return Status::Ok;
    }
    return Status::Unknown;
}

}  // namespace anyfile
