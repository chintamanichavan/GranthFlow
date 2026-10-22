#include "pdf/parser.hpp"
#include "check.hpp"

using namespace anyfile::pdf;

static ObjPtr parse(const std::string& s, Parser::Resolver r = nullptr) { Parser p(s, 0, std::move(r)); return p.parse(); }

TEST(reference_lookahead) {
    ObjPtr o = parse("1 0 R");
    CHECK(o->isRef()); CHECK_EQ(o->ref.num, 1); CHECK_EQ(o->ref.gen, 0);
}

TEST(integers_before_an_operator_are_not_a_reference) {
    Parser p("1 0 Td");
    ObjPtr a = p.parse(), b = p.parse(), c = p.parse();
    CHECK(a->isInt()); CHECK_EQ(a->intValue(), 1);
    CHECK(b->isInt()); CHECK_EQ(b->intValue(), 0);
    CHECK(c->isOperator("Td"));
}

TEST(nested_dict_and_array) {
    ObjPtr o = parse("<< /A [1 2 /X (s)] /B << /C true /D null >> >>");
    CHECK(o->isDict());
    ObjPtr a = o->get("A");
    CHECK(a->isArray()); CHECK_EQ(a->array.size(), size_t(4));
    CHECK(a->array[2]->isName("X")); CHECK_EQ(a->array[3]->str, "s");
    CHECK(o->get("B")->get("C")->boolean);
    CHECK(o->get("B")->get("D")->isNull());
    CHECK(o->get("Missing")->isNull());   // never nullptr
}

TEST(stream_with_correct_length) {
    ObjPtr o = parse("<< /Length 5 >>\nstream\nhello\nendstream");
    CHECK(o->isStream()); CHECK_EQ(o->raw, "hello");
}

TEST(stream_with_wrong_length_falls_back_to_endstream_search) {
    CHECK_EQ(parse("<< /Length 99 >>\nstream\nhello\nendstream")->raw, "hello");
    CHECK_EQ(parse("<< /Length 2 >>\nstream\nhello\nendstream")->raw, "hello");
    CHECK_EQ(parse("<< >>\nstream\r\nhello\r\nendstream")->raw, "hello");
}

TEST(stream_length_via_resolver) {
    auto resolver = [](const Ref& r) { return r.num == 9 ? makeInt(5) : makeNull(); };
    ObjPtr o = parse("<< /Length 9 0 R >>\nstream\nhello world\nendstream", resolver);
    CHECK_EQ(o->raw, "hello world");   // Length says 5, but "endstream" does not follow -> search wins
}

TEST(parse_indirect_object) {
    Parser p("7 0 obj\n<< /K 1 >>\nendobj\n8 0 obj 42 endobj");
    int num, gen; ObjPtr o;
    CHECK(p.parseIndirect(num, gen, o));
    CHECK_EQ(num, 7); CHECK(o->isDict());
    CHECK(p.parseIndirect(num, gen, o));
    CHECK_EQ(num, 8); CHECK_EQ(o->intValue(), 42);
    CHECK(!p.parseIndirect(num, gen, o));
}

TEST(keywords_become_operators_and_literals) {
    Parser p("true false null BT");
    CHECK(p.parse()->boolean); CHECK(!p.parse()->boolean); CHECK(p.parse()->isNull()); CHECK(p.parse()->isOperator("BT"));
    CHECK(p.parse() == nullptr);
}

TEST(serialize_round_trips_special_characters) {
    CHECK_EQ(serialize(makeString("a(b)\\c\n")), "(a\\(b\\)\\\\c\\n)");
    CHECK_EQ(serialize(makeName("A B/C")), "/A#20B#2FC");
    CHECK_EQ(serialize(makeNumber(1.5, false)), "1.5");
    CHECK_EQ(serialize(makeInt(-7)), "-7");
    CHECK_EQ(serialize(makeRef(3, 0)), "3 0 R");
    CHECK_EQ(serialize(makeArray({makeInt(1), makeName("X")})), "[1 /X]");
    CHECK_EQ(serialize(makeDict({{"A", makeInt(1)}})), "<< /A 1 >>");
    ObjPtr back = parse(serialize(makeString("\x01\xff()")));
    CHECK_EQ(back->str, std::string("\x01\xff()"));
}

TEST(make_stream_sets_length) {
    ObjPtr s = makeStream({}, "abc");
    CHECK_EQ(s->get("Length")->intValue(), 3);
    CHECK_CONTAINS(serialize(s), "stream\nabc\nendstream");
}

TEST(unbalanced_input_terminates) {
    ObjPtr o = parse("[ 1 2 << /A 3");
    CHECK(o->isArray());
    CHECK(parse("<< /A >>")->isDict());
    CHECK(parse("]")->isOperator());
}
