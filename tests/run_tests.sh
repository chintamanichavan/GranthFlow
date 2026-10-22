#!/bin/sh
# Smoke tests for anyfile. Usage: tests/run_tests.sh [path/to/anyfile]
set -eu
A=${1:-"$(dirname "$0")/../build/anyfile"}
A=$(cd "$(dirname "$A")" && pwd)/$(basename "$A")
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T"
fail() { echo "FAIL: $1"; exit 1; }
expect() { # expect <description> <expected-substring> <command...>
  desc=$1; want=$2; shift 2
  got=$("$@" 2>&1) || true
  case "$got" in *"$want"*) echo "ok   $desc";; *) echo "got: $got"; fail "$desc";; esac
}

# --- text ---
printf 'alpha\nbeta\ngamma\n' > plain.txt
expect "text detect" "type:       text" "$A" plain.txt
expect "text insert" "inserted at line 2" "$A" plain.txt insert 2 "inserted"
expect "text replace" "replaced 1" "$A" plain.txt replace gamma GAMMA
expect "text append" "5 lines" "$A" plain.txt append delta
expect "text lines" "4	GAMMA" "$A" plain.txt lines
expect "text delete" "deleted lines 1-2" "$A" plain.txt delete 1:2
expect "text regex" "changed 3 lines" "$A" plain.txt replace-regex '^(\w+)$' '[$1]' --all
[ "$(head -1 plain.txt)" = "[beta]" ] || fail "regex result"

# --- markdown ---
printf '# Title\n\nIntro [l](http://x).\n\n## A\n\nbody a\n\n## B\n\nbody b\n' > n.md
expect "md detect" "type:       markdown" "$A" n.md
expect "md outline" "5	  A" "$A" n.md outline
expect "md section" "body b" "$A" n.md section B
expect "md replace-section" "replaced section" "$A" n.md replace-section A 'new a'
expect "md section after" "new a" "$A" n.md section a
expect "md add-section" "added section" "$A" n.md add-section 2 C "body c"
expect "md links" "http://x" "$A" n.md links
expect "md render" "Title" "$A" n.md render --no-color

# --- binary ---
printf '\177ELF\001\002\000hello\000' > b.bin
expect "bin detect" "type:       binary" "$A" b.bin
expect "bin strings" "hello" "$A" b.bin strings 4
expect "bin patch" "patched 2 bytes" "$A" b.bin patch 0x7 4a4f
expect "bin after patch" "JOllo" "$A" b.bin strings 4

# --- pdf (hand-written, deliberately wrong xref offsets to exercise the scan fallback) ---
cat > t.pdf <<'PDF'
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 300 200] >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj
4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj
5 0 obj << /Length 73 >>
stream
BT /F1 18 Tf 20 150 Td (Hello PDF World) Tj 0 -30 Td [(Second) -300 (line)] TJ ET
endstream
endobj
6 0 obj << /Title (Tiny Test) /Author (anyfile) >> endobj
xref
0 7
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000139 00000 n 
0000000240 00000 n 
0000000310 00000 n 
0000000440 00000 n 
trailer << /Size 7 /Root 1 0 R /Info 6 0 R >>
startxref
500
%%EOF
PDF
expect "pdf detect" "type:       pdf" "$A" t.pdf
expect "pdf text" "Hello PDF World" "$A" t.pdf text
expect "pdf TJ spacing" "Second line" "$A" t.pdf text
expect "pdf meta" "Title: Tiny Test" "$A" t.pdf meta
expect "pdf set-meta" "saved" "$A" t.pdf set-meta Title "Edited"
expect "pdf meta after" "Title: Edited" "$A" t.pdf meta
expect "pdf replace" "1 replacement" "$A" t.pdf replace "Hello PDF World" "Goodbye"
expect "pdf text after" "Goodbye" "$A" t.pdf text
expect "pdf add-page" "added page 2" "$A" t.pdf add-page 'New page\nline two'
expect "pdf pages" "2	obj" "$A" t.pdf pages
expect "pdf new page text" "line two" "$A" t.pdf text 2
expect "pdf add-note" "added note" "$A" t.pdf add-note 1 "hi"
expect "pdf delete-page --out" "deleted page 2" "$A" t.pdf delete-page 2 --out t2.pdf
expect "pdf out has 1 page" "1 pages" "$A" t2.pdf info
expect "pdf original untouched" "2 pages" "$A" t.pdf info
expect "pdf help" "set-meta" "$A" t.pdf help

# --- epub (built by Python's zipfile, so the reader is checked against an independent writer) ---
python3 - <<'PY'
import zipfile
z = zipfile.ZipFile("b.epub", "w")
z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
d = zipfile.ZIP_DEFLATED
z.writestr("META-INF/container.xml", '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>', d)
z.writestr("OPS/book.opf", """<package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>
<dc:title>Smoke Book</dc:title><dc:creator>Tester</dc:creator></metadata>
<manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
<item id="n" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="a"/><itemref idref="b"/></spine></package>""", d)
z.writestr("OPS/a.xhtml", "<html><head><title>a</title></head><body><h1>First</h1>" + "<p>The quick brown fox.</p>" * 40 + "</body></html>", d)
z.writestr("OPS/b.xhtml", "<html><body><h1>Second</h1><p>Lazy dog &amp; friends.</p></body></html>", d)
z.writestr("OPS/nav.xhtml", '<html><body><nav><ol><li><a href="a.xhtml">Start</a></li></ol></nav></body></html>', d)
z.close()
PY
expect "epub detect" "type:       epub" "$A" b.epub
expect "epub info" "version 3.0, 2 chapters, 6 files" "$A" b.epub info
expect "epub chapters nav" "1	Start	OPS/a.xhtml" "$A" b.epub chapters
expect "epub chapters heading" "2	Second	OPS/b.xhtml" "$A" b.epub chapters
expect "epub text" "Lazy dog & friends." "$A" b.epub text 2
expect "epub meta" "title: Smoke Book" "$A" b.epub meta
expect "epub set-meta" "saved" "$A" b.epub set-meta title "Edited Book"
expect "epub meta after" "title: Edited Book" "$A" b.epub meta
expect "epub replace" "chapter 2: 1 replacement" "$A" b.epub replace "Lazy dog" "Sleepy cat"
expect "epub replace --all" "chapter 1: 40 replacements" "$A" b.epub replace fox wolf --all --out b2.epub
expect "epub text after" "Sleepy cat & friends." "$A" b.epub text 2
expect "epub original untouched" "quick brown fox" "$A" b.epub text 1
# The rewritten archives must satisfy independent zip readers, with mimetype first and uncompressed.
unzip -tq b2.epub >/dev/null || fail "epub: unzip rejects rewritten archive"
python3 - <<'PY' || fail "epub: python zipfile rejects rewritten archive"
import zipfile, sys
z = zipfile.ZipFile("b2.epub")
assert z.testzip() is None
first = z.infolist()[0]
assert first.filename == "mimetype" and first.compress_type == zipfile.ZIP_STORED
assert z.read("mimetype") == b"application/epub+zip"
assert z.read("OPS/a.xhtml").count(b"wolf") == 40
assert b"Sleepy cat &amp; friends" in z.read("OPS/b.xhtml")
assert b"Edited Book" in z.read("OPS/book.opf")
PY
echo "ok   epub rewritten archive verified by unzip and python"

expect "forced type" "type:       text" "$A" --as text t.pdf info
echo "all tests passed"
