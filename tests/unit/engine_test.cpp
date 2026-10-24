// The byte-in/byte-out façade every platform binding sits on. These cases are the contract the
// SwiftUI bridge and the WebAssembly build both rely on.
#include "core/engine.hpp"

#include "check.hpp"
#include "epub_fixture.hpp"
#include "fixtures.hpp"

using namespace anyfile;

// ---------------------------------------------------------------- detection

TEST(detect_kind_from_bytes_and_name) {
    CHECK_EQ(detectKind("%PDF-1.4\n", "a.pdf"), "pdf");
    CHECK_EQ(detectKind("   %PDF-1.4\n", "a.bin"), "pdf");            // magic beats extension
    CHECK_EQ(detectKind("# hi", "notes.md"), "markdown");
    CHECK_EQ(detectKind("# hi", "notes.MARKDOWN"), "markdown");
    CHECK_EQ(detectKind("plain", "a.txt"), "text");
    CHECK_EQ(detectKind("plain", "noext"), "text");
    CHECK_EQ(detectKind(std::string("\x00\x01\x02", 3), "a.dat"), "binary");
    CHECK_EQ(detectKind(epubBytes(), "book.epub"), "epub");
    CHECK_EQ(detectKind(epubBytes(), "book.zip"), "epub");            // the mimetype entry beats the extension
}

TEST(detect_kind_ignores_the_host_path_and_keeps_the_extension) {
    // The host hands over a display name, not a path; only its extension may matter.
    CHECK_EQ(detectKind("# hi", "/no/such/dir/notes.md"), "markdown");
    CHECK_EQ(detectKind("# hi", ""), "text");
}

// ---------------------------------------------------------------- commands

TEST(commands_for_kind_lists_the_kinds_own_then_the_common_ones) {
    auto names = [](const std::string& kind) {
        std::string joined;
        for (const auto& c : commandsForKind(kind)) joined += c.name + " ";
        return joined;
    };
    CHECK_CONTAINS(names("pdf"), "pages");
    CHECK_CONTAINS(names("pdf"), "hex");                // every file gets the byte commands
    CHECK_CONTAINS(names("epub"), "chapters");
    CHECK_CONTAINS(names("markdown"), "outline");
    CHECK_CONTAINS(names("text"), "grep");
    CHECK_CONTAINS(names("binary"), "strings");
    CHECK(commandsForKind("binary").size() > 0);
    CHECK_EQ(commandsForKind("nonsense").size(), size_t(0));   // no handler, and so no commands

    // The kind's own commands come first, the common ones after.
    const auto pdf = commandsForKind("pdf");
    size_t pages = 0, hex = 0;
    for (size_t i = 0; i < pdf.size(); ++i) {
        if (pdf[i].name == "pages") pages = i;
        if (pdf[i].name == "hex") hex = i;
    }
    CHECK(pages < hex);
}

// ---------------------------------------------------------------- running

TEST(run_reports_output_and_leaves_the_bytes_alone) {
    auto r = runOnBytes("count", {}, "one\ntwo\nthree\n", "a.txt", "");
    CHECK_EQ(int(r.status), int(Status::Ok));
    CHECK(!r.didChange);
    CHECK(r.changed.empty());
    CHECK(r.error.empty());
    CHECK_CONTAINS(r.output, "3");
}

TEST(run_returns_the_new_bytes_when_a_command_rewrites_the_file) {
    auto r = runOnBytes("replace", {"colour", "color", "--all"}, "colour and colour\n", "a.txt", "");
    CHECK_EQ(int(r.status), int(Status::Ok));
    CHECK(r.didChange);
    CHECK_EQ(r.changed, "color and color\n");
}

TEST(run_honours_a_forced_kind) {
    // Text bytes read as binary give a hex dump rather than lines.
    auto r = runOnBytes("info", {}, "plain text here\n", "a.txt", "binary");
    CHECK_EQ(int(r.status), int(Status::Ok));
    CHECK_CONTAINS(r.output, "binary");
}

TEST(run_drops_out_so_a_host_that_passed_bytes_gets_the_result_back) {
    // `--out other.txt` would ask the engine to write a copy to a path the host never named.
    // It is dropped, and the change comes back in `changed` instead.
    auto r = runOnBytes("replace", {"a", "b", "--out", "other.txt", "--all"}, "aaa\n", "a.txt", "");
    CHECK_EQ(int(r.status), int(Status::Ok));
    CHECK(r.didChange);
    CHECK_EQ(r.changed, "bbb\n");
    CHECK_EQ(int(runOnBytes("replace", {"a", "b", "-o", "other.txt", "--all"}, "aaa\n", "a.txt", "").status), int(Status::Ok));
}

TEST(run_explains_an_unknown_command_in_terms_of_the_files_kind) {
    auto r = runOnBytes("outline", {}, "plain\n", "a.txt", "");   // a markdown command on a text file
    CHECK_EQ(int(r.status), int(Status::Unknown));
    CHECK_CONTAINS(r.error, "outline");
    CHECK_CONTAINS(r.error, "text");
    CHECK(!r.didChange);
}

TEST(run_reports_bad_usage_without_changing_anything) {
    auto r = runOnBytes("replace", {}, "aaa\n", "a.txt", "");      // missing both arguments
    CHECK_EQ(int(r.status), int(Status::BadUsage));
    CHECK(!r.didChange);
    CHECK(!r.error.empty());
}

TEST(run_rejects_a_kind_that_has_no_handler) {
    auto r = runOnBytes("info", {}, "x", "a.txt", "nonsense");
    CHECK_EQ(int(r.status), int(Status::BadUsage));
    CHECK_CONTAINS(r.error, "unknown file kind");
}

// ---------------------------------------------------------------- real formats

TEST(run_reads_and_rewrites_an_epub_held_in_memory) {
    const std::string book = epubBytes();
    auto chapters = runOnBytes("chapters", {}, book, "book.epub", "");
    CHECK_EQ(int(chapters.status), int(Status::Ok));
    CHECK(!chapters.didChange);

    auto meta = runOnBytes("set-meta", {"title", "Second Edition"}, book, "book.epub", "");
    CHECK_EQ(int(meta.status), int(Status::Ok));
    CHECK(meta.didChange);
    CHECK(meta.changed.size() > 0);
    // The rewritten archive is still an EPUB, and the new title is in it.
    CHECK_EQ(detectKind(meta.changed, "book.epub"), "epub");
    CHECK_CONTAINS(runOnBytes("meta", {}, meta.changed, "book.epub", "").output, "Second Edition");
}

TEST(run_patches_bytes_of_a_binary) {
    auto r = runOnBytes("patch", {"1", "ff"}, std::string("\x00\x01\x02\x03", 4), "a.dat", "");
    CHECK_EQ(int(r.status), int(Status::Ok));
    CHECK(r.didChange);
    CHECK_EQ(r.changed, std::string("\x00\xff\x02\x03", 4));
}

TEST(staging_is_cleaned_up_after_every_run) {
    // Nothing the façade stages may outlive the call; a thousand runs must not leave a thousand
    // directories behind in the temp folder.
    namespace fs = std::filesystem;
    auto staged = [] {
        size_t n = 0;
        std::error_code ec;
        for (const auto& e : fs::directory_iterator(fs::temp_directory_path(), ec)) {
            if (e.path().filename().string().rfind("anyfile-", 0) == 0) ++n;
        }
        return n;
    };
    const size_t before = staged();
    for (int i = 0; i < 50; ++i) (void)runOnBytes("count", {}, "x\n", "a.txt", "");
    CHECK_EQ(staged(), before);
}
