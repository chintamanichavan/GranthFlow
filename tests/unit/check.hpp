// Minimal unit-test harness: TEST(name) registers a case, CHECK/CHECK_EQ record failures,
// main() runs everything and exits non-zero if anything failed. One executable per module.
#pragma once
#include <cstdio>
#include <string>
#include <vector>

namespace check {
struct Case { const char* name; void (*fn)(); };
inline std::vector<Case>& cases() { static std::vector<Case> c; return c; }
inline int& failures() { static int f = 0; return f; }
struct Register { Register(const char* n, void (*f)()) { cases().push_back({n, f}); } };
template <class T> std::string show(const T& v) { if constexpr (std::is_convertible_v<T, std::string>) return "\"" + std::string(v) + "\""; else return std::to_string(v); }
}  // namespace check

#define TEST(name) static void name(); static check::Register name##_reg(#name, name); static void name()
#define CHECK(cond) do { if (!(cond)) { std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++check::failures(); } } while (0)
#define CHECK_EQ(a, b) do { auto va_ = (a); auto vb_ = (b); if (!(va_ == vb_)) { \
    std::printf("  FAIL %s:%d: %s == %s\n    left:  %s\n    right: %s\n", __FILE__, __LINE__, #a, #b, check::show(va_).c_str(), check::show(vb_).c_str()); ++check::failures(); } } while (0)
#define CHECK_CONTAINS(hay, needle) do { std::string h_ = (hay); std::string n_ = (needle); if (h_.find(n_) == std::string::npos) { \
    std::printf("  FAIL %s:%d: expected to find %s\n    in: %s\n", __FILE__, __LINE__, check::show(n_).c_str(), check::show(h_).c_str()); ++check::failures(); } } while (0)

int main() {
    int failedCases = 0;
    for (const auto& c : check::cases()) {
        int before = check::failures();
        c.fn();
        if (check::failures() != before) { ++failedCases; std::printf("FAIL %s\n", c.name); }
    }
    std::printf("%zu cases, %d failed\n", check::cases().size(), failedCases);
    return failedCases ? 1 : 0;
}
