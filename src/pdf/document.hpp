// A loaded PDF: cross-reference parsing, object access, page tree, and incremental-update saving.
#pragma once
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "object.hpp"

namespace anyfile::pdf {

struct PageInfo {
    Ref ref;                  // the page object (may be {0,0} if it was a direct object)
    ObjPtr dict;              // the page dictionary
    ObjPtr resources;         // effective (possibly inherited) /Resources
    ObjPtr mediaBox;          // effective /MediaBox
    Ref parent;               // owning /Pages node
};

class Document {
public:
    bool load(const std::string& path, std::string& error);

    // Object access. Resolves references (following chains), returns Null objects instead of nullptr.
    ObjPtr resolve(const ObjPtr& obj);
    ObjPtr object(int num);
    ObjPtr trailer() const { return trailer_; }
    ObjPtr catalog();
    ObjPtr info();
    std::optional<Ref> infoRef() const;
    bool isEncrypted() const { return trailer_ && trailer_->has("Encrypt"); }
    bool usesXrefStream() const { return xrefStream_; }
    std::string version() const { return version_; }
    size_t fileSize() const { return data_.size(); }
    int objectCount() const { return nextObjNum_ - 1; }
    const std::set<int>& knownObjectNumbers();

    // Decoded stream contents (filters applied).
    std::string streamData(const ObjPtr& stream, bool* complete = nullptr);

    std::vector<PageInfo> pages();

    // --- modification (queued as an incremental update) ---
    int allocateObject();
    void setObject(int num, int gen, ObjPtr value);
    void setTrailerInfo(Ref infoRef) { newInfo_ = infoRef; }
    bool hasPendingChanges() const { return !updates_.empty(); }
    bool save(const std::string& path, std::string& error);

private:
    struct XrefEntry { int type = 0; long long field2 = 0; int field3 = 0; };  // type1: offset/gen, type2: stream num/index

    bool parseXrefChain(long long startOffset);
    bool parseXrefTable(size_t pos, std::vector<long long>& more);
    bool parseXrefStream(size_t pos, std::vector<long long>& more);
    void mergeTrailer(const ObjPtr& dict);
    void scanAllObjects();          // fallback when the xref is unusable
    ObjPtr loadFromObjectStream(int streamNum, int index, int wantedNum);
    ObjPtr parseAt(size_t offset, int expectedNum);
    void collectPages(const ObjPtr& nodeRef, Ref parent, ObjPtr resources, ObjPtr mediaBox,
                      std::vector<PageInfo>& out, std::set<int>& visited, int depth);

    std::string data_;
    std::string version_;
    std::map<int, XrefEntry> xref_;
    std::map<int, ObjPtr> cache_;
    std::map<int, std::vector<std::pair<int, ObjPtr>>> objStmCache_;  // parsed object streams
    std::set<int> knownNums_;
    bool scanned_ = false;
    bool xrefStream_ = false;
    bool xrefBroken_ = false;
    ObjPtr trailer_ = makeDict();
    long long lastStartXref_ = -1;
    int nextObjNum_ = 1;

    struct Update { int num; int gen; ObjPtr value; };
    std::vector<Update> updates_;
    std::optional<Ref> newInfo_;
};

}  // namespace anyfile::pdf
