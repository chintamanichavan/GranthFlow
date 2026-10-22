// PDF object model: the eight basic PDF value types plus streams and references.
#pragma once
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace anyfile::pdf {

struct Object;
using ObjPtr = std::shared_ptr<Object>;

struct Ref {
    int num = 0;
    int gen = 0;
    bool operator<(const Ref& o) const { return num != o.num ? num < o.num : gen < o.gen; }
    bool operator==(const Ref& o) const { return num == o.num && gen == o.gen; }
};

enum class Type { Null, Bool, Number, String, Name, Array, Dict, Stream, Ref, Operator };

struct Object {
    Type type = Type::Null;
    bool boolean = false;
    double number = 0;
    bool isInteger = false;
    std::string str;                       // String bytes, Name (no leading '/'), or Operator keyword
    std::vector<ObjPtr> array;
    std::map<std::string, ObjPtr> dict;    // Dict and Stream
    std::string raw;                       // Stream: undecoded bytes
    Ref ref;

    bool isNull() const { return type == Type::Null; }
    bool isNumber() const { return type == Type::Number; }
    bool isInt() const { return type == Type::Number && isInteger; }
    bool isName(const char* n = nullptr) const { return type == Type::Name && (!n || str == n); }
    bool isString() const { return type == Type::String; }
    bool isArray() const { return type == Type::Array; }
    bool isDict() const { return type == Type::Dict || type == Type::Stream; }
    bool isStream() const { return type == Type::Stream; }
    bool isRef() const { return type == Type::Ref; }
    bool isOperator(const char* op = nullptr) const { return type == Type::Operator && (!op || str == op); }

    int intValue(int def = 0) const { return isNumber() ? static_cast<int>(number) : def; }
    double numValue(double def = 0) const { return isNumber() ? number : def; }

    // Dict lookup without resolving references. Returns a Null object (never nullptr) when absent.
    ObjPtr get(const std::string& key) const;
    bool has(const std::string& key) const { return isDict() && dict.count(key) > 0; }
};

ObjPtr makeNull();
ObjPtr makeBool(bool b);
ObjPtr makeNumber(double n, bool integer);
ObjPtr makeInt(long long n);
ObjPtr makeString(std::string s);
ObjPtr makeName(std::string n);
ObjPtr makeArray(std::vector<ObjPtr> items = {});
ObjPtr makeDict(std::map<std::string, ObjPtr> entries = {});
ObjPtr makeStream(std::map<std::string, ObjPtr> entries, std::string raw);
ObjPtr makeRef(int num, int gen);
ObjPtr makeOperator(std::string op);

// Serialize an object back to PDF syntax (used when writing incremental updates).
std::string serialize(const ObjPtr& obj);
std::string describe(const ObjPtr& obj, int depth = 0);  // human-readable, for `info`

}  // namespace anyfile::pdf
