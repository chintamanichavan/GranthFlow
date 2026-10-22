#pragma once
#include <memory>

#include "../core/handler.hpp"
#include "../pdf/document.hpp"

namespace anyfile {

class PdfHandler : public ByteHandler {
public:
    explicit PdfHandler(std::string path) : ByteHandler(std::move(path)) {}
    std::string kind() const override { return "pdf"; }
    std::vector<Command> commands() const override;
    Status run(const std::string& cmd, const std::vector<std::string>& args, std::ostream& out, std::ostream& err) override;

private:
    bool open(std::ostream& err);
    bool commit(const std::vector<std::string>& args, std::ostream& out, std::ostream& err);
    void describe(std::ostream& out) override;
    std::string outputPath(const std::vector<std::string>& args) const;
    std::unique_ptr<pdf::Document> doc_;
};

}  // namespace anyfile
