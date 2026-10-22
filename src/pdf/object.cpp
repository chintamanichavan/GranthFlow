#include "object.hpp"

#include <cmath>
#include <cstdio>
#include <sstream>

namespace anyfile::pdf {

static ObjPtr theNull = std::make_shared<Object>();

ObjPtr Object::get(const std::string& key) const {
    if (!isDict()) return theNull;
    auto it = dict.find(key);
    return it == dict.end() ? theNull : it->second;
}

ObjPtr makeNull() { return std::make_shared<Object>(); }
ObjPtr makeBool(bool b) { auto o = makeNull(); o->type = Type::Bool; o->boolean = b; return o; }
ObjPtr makeNumber(double n, bool integer) { auto o = makeNull(); o->type = Type::Number; o->number = n; o->isInteger = integer; return o; }
ObjPtr makeInt(long long n) { return makeNumber(static_cast<double>(n), true); }
ObjPtr makeString(std::string s) { auto o = makeNull(); o->type = Type::String; o->str = std::move(s); return o; }
ObjPtr makeName(std::string n) { auto o = makeNull(); o->type = Type::Name; o->str = std::move(n); return o; }
ObjPtr makeArray(std::vector<ObjPtr> items) { auto o = makeNull(); o->type = Type::Array; o->array = std::move(items); return o; }
ObjPtr makeDict(std::map<std::string, ObjPtr> e) { auto o = makeNull(); o->type = Type::Dict; o->dict = std::move(e); return o; }
ObjPtr makeStream(std::map<std::string, ObjPtr> e, std::string raw) {
    auto o = makeNull(); o->type = Type::Stream; o->dict = std::move(e); o->raw = std::move(raw);
    o->dict["Length"] = makeInt(static_cast<long long>(o->raw.size()));
    return o;
}
ObjPtr makeRef(int num, int gen) { auto o = makeNull(); o->type = Type::Ref; o->ref = {num, gen}; return o; }
ObjPtr makeOperator(std::string op) { auto o = makeNull(); o->type = Type::Operator; o->str = std::move(op); return o; }

static std::string serializeNumber(const Object& o) {
    if (o.isInteger) return std::to_string(static_cast<long long>(o.number));
    char buf[64];
    std::snprintf(buf, sizeof buf, "%.4f", o.number);
    std::string s = buf;
    while (!s.empty() && s.back() == '0') s.pop_back();
    if (!s.empty() && s.back() == '.') s.pop_back();
    return s.empty() ? "0" : s;
}

static std::string serializeName(const std::string& n) {
    std::string out = "/";
    for (unsigned char c : n) {
        bool delim = c == '(' || c == ')' || c == '<' || c == '>' || c == '[' || c == ']' ||
                     c == '{' || c == '}' || c == '/' || c == '%' || c == '#';
        if (c < 33 || c > 126 || delim) {
            char buf[4];
            std::snprintf(buf, sizeof buf, "#%02X", c);
            out += buf;
        } else {
            out += static_cast<char>(c);
        }
    }
    return out;
}

static std::string serializeString(const std::string& s) {
    std::string out = "(";
    for (unsigned char c : s) {
        switch (c) {
            case '(': out += "\\("; break;
            case ')': out += "\\)"; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 32 || c > 126) {
                    char buf[6];
                    std::snprintf(buf, sizeof buf, "\\%03o", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out + ")";
}

std::string serialize(const ObjPtr& obj) {
    if (!obj) return "null";
    const Object& o = *obj;
    switch (o.type) {
        case Type::Null: return "null";
        case Type::Bool: return o.boolean ? "true" : "false";
        case Type::Number: return serializeNumber(o);
        case Type::String: return serializeString(o.str);
        case Type::Name: return serializeName(o.str);
        case Type::Ref: return std::to_string(o.ref.num) + " " + std::to_string(o.ref.gen) + " R";
        case Type::Operator: return o.str;
        case Type::Array: {
            std::string out = "[";
            for (size_t i = 0; i < o.array.size(); ++i) {
                if (i) out += " ";
                out += serialize(o.array[i]);
            }
            return out + "]";
        }
        case Type::Dict:
        case Type::Stream: {
            std::string out = "<<";
            for (const auto& [k, v] : o.dict) {
                out += " " + serializeName(k) + " " + serialize(v);
            }
            out += " >>";
            if (o.type == Type::Stream) {
                out += "\nstream\n";
                out += o.raw;
                out += "\nendstream";
            }
            return out;
        }
    }
    return "null";
}

std::string describe(const ObjPtr& obj, int depth) {
    if (!obj) return "null";
    const Object& o = *obj;
    std::string pad(static_cast<size_t>(depth) * 2, ' ');
    switch (o.type) {
        case Type::Stream: {
            std::ostringstream ss;
            ss << "stream(" << o.raw.size() << " bytes) ";
            auto d = makeDict(o.dict);
            ss << describe(d, depth);
            return ss.str();
        }
        case Type::Dict: {
            if (o.dict.empty()) return "<< >>";
            std::string out = "<<\n";
            for (const auto& [k, v] : o.dict) out += pad + "  /" + k + " " + describe(v, depth + 1) + "\n";
            return out + pad + ">>";
        }
        case Type::Array: {
            if (o.array.size() > 12) return "[array of " + std::to_string(o.array.size()) + "]";
            return serialize(obj);
        }
        default: return serialize(obj);
    }
}

}  // namespace anyfile::pdf
