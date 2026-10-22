#!/usr/bin/env python3
"""Measure anyfile on large inputs. Usage: tests/bench.py [path/to/anyfile]

Generates a 400-page PDF (Flate content streams), a 200-chapter EPUB, a 50 MB text file,
a 10 MB Markdown file and a 50 MB binary file in a temp directory, then times representative commands. Prints a table.
"""
import os, random, shutil, subprocess, sys, tempfile, time, zipfile, zlib

A = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "build", "anyfile"))
D = tempfile.mkdtemp(prefix="anyfile_bench_")
random.seed(1)
WORDS = "the quick brown fox jumps over the lazy dog lorem ipsum dolor sit amet consectetur".split()

def make_pdf(path, pages):
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offs = {}
    def add(num, body):
        offs[num] = len(out); out.extend(f"{num} 0 obj\n".encode() + body + b"\nendobj\n")
    kids = []
    add(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    add(3, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    next_num = 4
    for p in range(pages):
        lines = []
        for i in range(45):
            lines.append(f"({' '.join(random.choice(WORDS) for _ in range(12))}) Tj T*")
        content = ("BT /F1 10 Tf 12 TL 40 750 Td\n" + "\n".join(lines) + "\nET").encode()
        z = zlib.compress(content)
        add(next_num, f"<< /Length {len(z)} /Filter /FlateDecode >>\nstream\n".encode() + z + b"\nendstream")
        add(next_num + 1, f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents {next_num} 0 R >>".encode())
        kids.append(f"{next_num + 1} 0 R"); next_num += 2
    add(2, f"<< /Type /Pages /Kids [{' '.join(kids)}] /Count {pages} >>".encode())
    xref = len(out)
    out.extend(f"xref\n0 {next_num}\n0000000000 65535 f \n".encode())
    for n in range(1, next_num):
        out.extend(f"{offs[n]:010d} 00000 n \n".encode())
    out.extend(f"trailer\n<< /Size {next_num} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    open(path, "wb").write(out)

def make_text(path, mb, markdown=False):
    with open(path, "w") as f:
        n = 0
        while n < mb * 1024 * 1024:
            if markdown and random.random() < 0.02:
                line = "## Section " + str(random.randint(1, 99999)) + "\n"
            else:
                line = " ".join(random.choice(WORDS) for _ in range(14)) + "\n"
            f.write(line); n += len(line)

def make_epub(path, chapters):
    z = zipfile.ZipFile(path, "w")
    z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip")
    d = zipfile.ZIP_DEFLATED
    z.writestr("META-INF/container.xml", '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>', d)
    items = "".join(f'<item id="c{i}" href="c{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(chapters))
    spine = "".join(f'<itemref idref="c{i}"/>' for i in range(chapters))
    z.writestr("OPS/book.opf", '<package version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>Bench</dc:title></metadata>'
               f'<manifest>{items}</manifest><spine>{spine}</spine></package>', d)
    for i in range(chapters):
        paras = "".join("<p>" + " ".join(random.choice(WORDS) for _ in range(80)) + "</p>\n" for _ in range(120))
        z.writestr(f"OPS/c{i}.xhtml", f"<html><head><title>c{i}</title></head><body><h1>Chapter {i + 1}</h1>\n{paras}</body></html>", d)
    z.close()

def timed(label, args):
    t0 = time.perf_counter()
    r = subprocess.run([A] + args, capture_output=True)
    dt = time.perf_counter() - t0
    ok = "ok" if r.returncode == 0 else f"exit {r.returncode}"
    print(f"{label:<48} {dt*1000:9.0f} ms   {ok}")
    return dt

try:
    pdf, txt, md, binf = (os.path.join(D, n) for n in ("big.pdf", "big.txt", "big.md", "big.bin"))
    epub = os.path.join(D, "big.epub")
    t0 = time.perf_counter()
    make_pdf(pdf, 400); make_epub(epub, 200); make_text(txt, 50); make_text(md, 10, markdown=True)
    with open(binf, "wb") as f: f.write(random.randbytes(50 * 1024 * 1024))
    print(f"fixtures generated in {time.perf_counter() - t0:.1f}s:  pdf {os.path.getsize(pdf)//1024} KiB, epub {os.path.getsize(epub)//1024} KiB, txt {os.path.getsize(txt)>>20} MiB, md {os.path.getsize(md)>>20} MiB, bin {os.path.getsize(binf)>>20} MiB\n")
    print(f"{'command':<48} {'time':>12}")
    timed("pdf info (400 pages)", [pdf, "info"])
    timed("pdf text, all pages", [pdf, "text", "--out", os.path.join(D, "out.txt")])
    timed("pdf text, one page", [pdf, "text", "200"])
    timed("pdf set-meta (incremental save)", [pdf, "set-meta", "Title", "Bench", "--out", os.path.join(D, "m.pdf")])
    timed("pdf add-page", [pdf, "add-page", "hello", "--out", os.path.join(D, "p.pdf")])
    timed("pdf replace --all (rewrites 400 streams)", [pdf, "replace", "fox", "cat", "--all", "--out", os.path.join(D, "r.pdf")])
    timed("epub info (200 chapters, 9 MiB of XHTML)", [epub, "info"])
    timed("epub chapters (reads every heading)", [epub, "chapters"])
    timed("epub text, all chapters", [epub, "text"])
    timed("epub text, one chapter", [epub, "text", "100"])
    timed("epub set-meta (rewrite archive)", [epub, "set-meta", "title", "Bench 2", "--out", os.path.join(D, "m.epub")])
    timed("epub replace --all (recompress 200 chapters)", [epub, "replace", "fox", "cat", "--all", "--out", os.path.join(D, "r.epub")])
    timed("text info (50 MiB)", [txt, "info"])
    timed("text grep", [txt, "grep", "lazy dog lorem$"])
    timed("text replace --all (50 MiB)", [txt, "replace", "fox", "cat", "--all"])
    timed("text insert line (rewrite file)", [txt, "insert", "1000", "inserted"])
    timed("markdown outline (10 MiB)", [md, "outline"])
    timed("markdown toc", [md, "toc"])
    timed("binary hex at 40 MiB offset", [binf, "hex", str(40 << 20), "256"])
    timed("binary strings (50 MiB)", [binf, "strings", "8"])
    timed("binary patch (rewrite file)", [binf, "patch", "0x100", "deadbeef"])
finally:
    shutil.rmtree(D, ignore_errors=True)
