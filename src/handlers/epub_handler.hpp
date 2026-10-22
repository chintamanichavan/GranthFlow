#pragma once
#include <memory>

#include "../core/handler.hpp"
#include "../epub/book.hpp"

namespace anyfile {

// EPUB: read chapters as plain text, inspect the archive, and edit text or metadata in place.
class EpubHandler : public ByteHandler {
public:
    explicit EpubHandler(std::string path) : ByteHandler(std::move(path)) {}
    std::string kind() const override { return "epub"; }
    std::vector<Command> commands() const override;
    Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) override;

private:
    bool open(std::ostream& err);
    bool commit(const std::vector<std::string>& args, std::ostream& out, std::ostream& err);
    void describe(std::ostream& out) override;
    std::unique_ptr<epub::Book> book_;
};

}  // namespace anyfile
