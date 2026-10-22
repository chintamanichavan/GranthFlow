#include "pdf/document.hpp"
#include "pdf/filters.hpp"
#include "check.hpp"
#include "fixtures.hpp"

using namespace anyfile::pdf;

static bool loadDoc(Document& d, const std::string& path) { std::string e; bool ok = d.load(path, e); if (!ok) std::printf("  load error: %s\n", e.c_str()); return ok; }

TEST(load_classic_xref) {
    TempDir t; Document d;
    CHECK(loadDoc(d, t.file("a.pdf", simpleDoc("BT ET").build())));
    CHECK_EQ(d.version(), "1.4");
    CHECK(!d.usesXrefStream()); CHECK(!d.isEncrypted());
    CHECK(d.catalog()->get("Type")->isName("Catalog"));
    CHECK_EQ(d.info()->get("Title")->str, "Fixture");
    CHECK(d.infoRef().has_value()); CHECK_EQ(d.infoRef()->num, 6);
    CHECK_EQ(d.objectCount(), 6);
    auto pages = d.pages();
    CHECK_EQ(pages.size(), size_t(1));
    CHECK_EQ(pages[0].ref.num, 3);
    CHECK(pages[0].mediaBox->isArray());          // inherited from the Pages node
    CHECK(pages[0].resources->get("Font")->isDict());
    CHECK_EQ(pages[0].parent.num, 2);
}

TEST(wrong_xref_offsets_fall_back_to_scan) {
    TempDir t; Document d;
    CHECK(loadDoc(d, t.file("bad.pdf", simpleDoc("BT ET").build(false))));
    CHECK(d.object(5)->isStream());
    CHECK_EQ(d.pages().size(), size_t(1));
    CHECK_EQ(d.info()->get("Author")->str, "unit");
}

TEST(no_xref_at_all_still_loads) {
    TempDir t; Document d;
    CHECK(loadDoc(d, t.file("noxref.pdf", simpleDoc("BT ET").build(true, false))));
    CHECK_EQ(d.pages().size(), size_t(1));
    CHECK(d.catalog()->isDict());
}

TEST(not_a_pdf_is_rejected) {
    TempDir t; Document d; std::string e;
    CHECK(!d.load(t.file("x.txt", "just text"), e));
    CHECK_CONTAINS(e, "not a PDF");
    CHECK(!d.load(t.path + "/missing.pdf", e));
}

TEST(xref_stream_and_object_streams) {
    TempDir t; Document d;
    CHECK(loadDoc(d, t.file("xs.pdf", xrefStreamDoc("BT ET"))));
    CHECK(d.usesXrefStream());
    CHECK(d.object(1)->get("Type")->isName("Catalog"));   // lives inside the object stream
    CHECK(d.object(4)->get("BaseFont")->isName("Helvetica"));
    CHECK_EQ(d.pages().size(), size_t(1));
    CHECK_EQ(d.pages()[0].ref.num, 3);
}

TEST(stream_data_applies_filters) {
    TempDir t; Document d;
    PdfBuilder b = simpleDoc("x");
    b.objs[4] = {5, streamObj("/Filter /FlateDecode", flateEncode("decoded content"))};
    CHECK(loadDoc(d, t.file("z.pdf", b.build())));
    bool complete = false;
    CHECK_EQ(d.streamData(d.object(5), &complete), "decoded content");
    CHECK(complete);
    CHECK_EQ(d.streamData(makeInt(1), &complete), "");
    CHECK(!complete);
}

TEST(resolve_follows_refs_and_survives_cycles) {
    TempDir t; Document d;
    PdfBuilder b = simpleDoc("x");
    b.objs.push_back({7, "7 0 R"});
    b.objs.push_back({8, "9 0 R"});
    b.objs.push_back({9, "8 0 R"});
    CHECK(loadDoc(d, t.file("c.pdf", b.build())));
    CHECK(d.resolve(makeRef(7, 0))->isNull());
    CHECK(d.resolve(makeRef(8, 0))->isNull());
    CHECK(d.resolve(makeRef(2, 0))->get("Type")->isName("Pages"));
    CHECK(d.resolve(makeRef(999, 0))->isNull());
    CHECK(d.resolve(nullptr)->isNull());
}

TEST(incremental_save_classic) {
    TempDir t; Document d;
    std::string original = simpleDoc("BT ET").build();
    std::string p = t.file("u.pdf", original);
    CHECK(loadDoc(d, p));
    int n = d.allocateObject();
    CHECK_EQ(n, 7);
    d.setObject(6, 0, makeDict({{"Title", makeString("Changed")}}));
    d.setObject(n, 0, makeDict({{"New", makeBool(true)}}));
    CHECK(d.hasPendingChanges());
    std::string err, out = t.path + "/u2.pdf";
    CHECK(d.save(out, err));
    std::string saved = TempDir::read(out);
    CHECK(saved.compare(0, original.size(), original) == 0);   // original bytes untouched
    CHECK_CONTAINS(saved, "/Prev ");
    CHECK_CONTAINS(saved, "xref\n6 2\n");                      // one subsection for objects 6 and 7

    Document d2;
    CHECK(loadDoc(d2, out));
    CHECK_EQ(d2.info()->get("Title")->str, "Changed");
    CHECK(d2.object(7)->get("New")->boolean);
    CHECK(d2.object(4)->get("BaseFont")->isName("Helvetica"));  // older objects still reachable through /Prev
    CHECK_EQ(d2.objectCount(), 7);
}

TEST(incremental_save_xref_stream) {
    TempDir t; Document d;
    std::string p = t.file("xs.pdf", xrefStreamDoc("BT ET"));
    CHECK(loadDoc(d, p));
    int n = d.allocateObject();
    d.setObject(n, 0, makeDict({{"K", makeInt(1)}}));
    std::string err, out = t.path + "/xs2.pdf";
    CHECK(d.save(out, err));
    CHECK_CONTAINS(TempDir::read(out), "/Type /XRef");
    Document d2;
    CHECK(loadDoc(d2, out));
    CHECK(d2.usesXrefStream());
    CHECK_EQ(d2.object(n)->get("K")->intValue(), 1);
    CHECK_EQ(d2.pages().size(), size_t(1));
}

TEST(set_trailer_info) {
    TempDir t; Document d;
    PdfBuilder b = simpleDoc("x");
    b.trailerExtra = "";   // no /Info
    CHECK(loadDoc(d, t.file("i.pdf", b.build())));
    CHECK(!d.infoRef().has_value());
    int n = d.allocateObject();
    d.setObject(n, 0, makeDict({{"Title", makeString("T")}}));
    d.setTrailerInfo({n, 0});
    std::string err, out = t.path + "/i2.pdf";
    CHECK(d.save(out, err));
    Document d2;
    CHECK(loadDoc(d2, out));
    CHECK_EQ(d2.info()->get("Title")->str, "T");
}

TEST(encrypted_is_detected_and_not_saved) {
    TempDir t; Document d;
    PdfBuilder b = simpleDoc("x");
    b.trailerExtra = " /Encrypt << /Filter /Standard >>";
    CHECK(loadDoc(d, t.file("e.pdf", b.build())));
    CHECK(d.isEncrypted());
    std::string err;
    CHECK(!d.save(t.path + "/e2.pdf", err));
    CHECK_CONTAINS(err, "encrypted");
}

TEST(page_tree_with_nested_pages_nodes) {
    TempDir t; Document d;
    PdfBuilder b;
    b.objs = {
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2, "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 3 /MediaBox [0 0 100 100] >>"},
        {3, "<< /Type /Pages /Parent 2 0 R /Kids [4 0 R] /Count 1 /MediaBox [0 0 50 50] >>"},
        {4, "<< /Type /Page /Parent 3 0 R >>"},
        {5, "<< /Type /Page /Parent 2 0 R >>"},
    };
    CHECK(loadDoc(d, t.file("tree.pdf", b.build())));
    auto pages = d.pages();
    CHECK_EQ(pages.size(), size_t(2));
    CHECK_EQ(pages[0].ref.num, 4); CHECK_EQ(pages[0].parent.num, 3);
    CHECK_EQ(pages[0].mediaBox->array[2]->intValue(), 50);    // nearest ancestor wins
    CHECK_EQ(pages[1].mediaBox->array[2]->intValue(), 100);
}

TEST(page_tree_cycle_terminates) {
    TempDir t; Document d;
    PdfBuilder b;
    b.objs = {{1, "<< /Type /Catalog /Pages 2 0 R >>"}, {2, "<< /Type /Pages /Kids [2 0 R 3 0 R] /Count 1 >>"}, {3, "<< /Type /Page /Parent 2 0 R >>"}};
    CHECK(loadDoc(d, t.file("cyc.pdf", b.build())));
    CHECK_EQ(d.pages().size(), size_t(1));
}
