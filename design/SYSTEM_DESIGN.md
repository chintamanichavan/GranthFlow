# anyfile — Engineering System Design

`anyfile` is a C++20 command-line tool that reads and modifies PDF, Markdown, plain-text and
arbitrary binary files with no third-party dependencies beyond zlib. This document is the
engineering design; `blender_system_design.py` renders the same design as a 3D diagram in Blender.

```
blender -b -P design/blender_system_design.py -- --render design/system_design.png
```

## 1. Goals and constraints

| Goal | Decision |
|---|---|
| One binary, any file | A `FileHandler` plug-in interface; the registry picks one per file |
| Read **and** modify | Every handler exposes both query and mutating commands |
| No heavy dependencies | Own PDF parser, own zip and XML readers for EPUB; zlib only (ships with macOS/Linux) |
| Never corrupt a file | Text/binary/EPUB: write temp + rename. PDF: append-only incremental updates |
| Tolerate broken files | PDF loader falls back from xref to a full object scan |

## 2. Layered architecture

```
 ┌──────────────────────────────────────────────────────────────────┐
 │ CLI            main.cpp — argv → file, command, args, --as       │
 ├──────────────────────────────────────────────────────────────────┤
 │ Core           Registry (magic + ext)   FileHandler iface   util │
 ├──────────────────────────────────────────────────────────────────┤
 │ Handlers   ByteHandler ◄─ TextHandler ◄─ MarkdownHandler         │
 │                 ▲                                                │
 │            PdfHandler   EpubHandler                              │
 ├──────────────────────────────────────────────────────────────────┤
 │ PDF engine  Lexer → Parser → Object model                        │
 │             Filters (Flate/A85/AHx + PNG predictors)             │
 │             Document (xref tables & streams, ObjStm, page tree,  │
 │                       incremental save)                          │
 │             Text (content-stream interpreter, ToUnicode CMaps,   │
 │                   literal replacement)                           │
 ├──────────────────────────────────────────────────────────────────┤
 │ EPUB engine Archive (zip: stored + deflate, copy-through save)   │
 │             XML Reader (tokens with byte offsets, entities)      │
 │             Book (container → package → spine, chapter text,     │
 │                   contents labels, metadata and text edits)      │
 ├──────────────────────────────────────────────────────────────────┤
 │ External    zlib            filesystem (the file on disk)        │
 └──────────────────────────────────────────────────────────────────┘
```

Arrows in the Blender diagram point from a module to what it depends on. Red arrows are
inheritance: Markdown *is a* text handler, text *is a* byte handler, so `notes.md` gets
`outline`/`section` **and** `grep`/`replace` **and** `hex`/`patch`.

## 3. Components

### CLI (`src/main.cpp`)
Parses `anyfile [--as type] <file> [command] [args]`. Defaults to `info`. Exit codes:
0 ok, 1 error, 2 bad usage / unknown command.

### Core (`src/core`)
- **FileHandler** — `kind()`, `commands()`, `run(cmd, args, out, err)`. Returns `Status::Unknown`
  for commands it does not own so the base class can try.
- **ByteHandler** — the universal base: `info`, `hex`, `strings`, `patch`, `patch-str`,
  `truncate`, `append-bytes`. Loads the whole file into memory (files are assumed to fit).
- **Registry** — detection order: `%PDF-` within the first 1 KiB → pdf; zip magic with a leading
  `mimetype` entry of `application/epub+zip` (or a `.epub` name) → epub; `.md`-family extension →
  markdown; printable heuristic over the first 8 KiB → text; else binary. `--as` overrides.
- **util** — atomic write (temp file + `rename`), line splitting that preserves CRLF vs LF,
  hex dump, escape handling for CLI text.

### Handlers (`src/handlers`)
- **TextHandler** — line model (`std::vector<std::string>` + newline style + trailing-newline flag).
  `show lines grep count replace replace-regex append insert set-line delete`.
- **MarkdownHandler** — heading parser (ATX and Setext, ignores fenced code), sections resolved by
  case-insensitive title. `render outline section replace-section add-section links toc`.
- **PdfHandler** — thin command layer over the PDF engine. `text pages meta object` read;
  `set-meta replace add-page add-note delete-page` modify; `--out` writes elsewhere.
- **EpubHandler** — thin command layer over the EPUB engine. `text chapters meta files cat` read;
  `set-meta replace` modify; `--out` writes elsewhere.

### EPUB engine (`src/epub`)
- **Archive** (`zip.cpp`) — reads the central directory, inflates entries on demand and checks
  their CRC. `put()` replaces or adds an entry; `serialize()` writes a new archive in which
  untouched entries are copied as compressed bytes, so an edit recompresses only what changed.
- **Reader** (`xml.cpp`) — a forgiving tokenizer for XML and XHTML. Every token carries its byte
  range in the source, which lets edits splice the original text instead of regenerating it.
- **Book** (`book.cpp`) — follows `container.xml` to the package file, reads Dublin Core metadata,
  the manifest and the spine, and takes chapter names from the navigation document or NCX.
  `htmlToText()` turns a chapter into plain text. `setMeta()` and `replaceText()` edit the package
  file or one chapter's text nodes and hand the result back to the archive.

### PDF engine (`src/pdf`)
- **Lexer** — PDF tokens: numbers (incl. `--5`, `.5`), literal/hex strings with escapes,
  `#xx` names, delimiters, keywords. Reused for content streams and CMaps.
- **Parser** — builds `Object`s. Two-token lookahead turns `n g R` into references. Streams:
  trusts `/Length` only if `endstream` follows; otherwise searches for it.
- **Object** — tagged union (`shared_ptr<Object>`), `serialize()` for writing, `describe()` for dumps.
- **Filters** — FlateDecode via zlib (tolerant of truncated data), ASCII85, ASCIIHex, PNG/TIFF
  predictors (required for xref streams written by modern producers).
- **Document** — see data flow below.
- **Text** — interprets `BT/ET Tf Td TD Tm T* Tj TJ ' "` and `Do` (form XObjects, recursive).
  Line breaks come from vertical text-matrix movement; word gaps from `TJ` kerning < −180.
  Fonts: `ToUnicode` CMaps (`bfchar`, `bfrange`, code-space byte width), else WinAnsi/MacRoman
  single-byte decoding. Unmapped CID glyphs are counted and reported, not guessed.

## 4. Data flows

### Read path (`anyfile doc.pdf text`)
1. Registry sniffs `%PDF-` → `PdfHandler`.
2. `Document::load` reads the file, finds the last `startxref`, walks the `/Prev` chain parsing
   xref **tables** or xref **streams** (newest entry wins), merging trailer dictionaries.
3. If anything fails (bad offsets, missing trailer), `scanAllObjects()` walks the file for
   `N G obj`, skipping over stream bodies, and also indexes objects inside `/ObjStm` streams.
   Objects are then loaded lazily and cached by number.
4. The page tree is walked from `/Root → /Pages → /Kids`, inheriting `/Resources` and `/MediaBox`.
5. Each page's content streams are decoded and run through the text interpreter.

### Modify path (`anyfile doc.pdf set-meta Title "X"`)
1. Build the new object (here: a copy of `/Info` with `Title` and `ModDate` changed).
2. `Document::setObject` queues it under the existing object number (or a freshly allocated one).
3. `Document::save` appends to the original bytes: the new objects, then either a classic
   `xref` table or an xref **stream** (matching what the file already used), a trailer with
   `/Prev` pointing at the previous xref, and a new `startxref`.
4. The result goes to a temp file and is renamed over the original, or to `--out`.

Because nothing in the original byte range is rewritten, a crash mid-save cannot damage the
source, and any reader can still reach every earlier revision through `/Prev`.

Text replacement (`replace`) rewrites string operands in content streams token-by-token so the
rest of the stream is byte-identical, then stores the stream re-compressed as a new object version.

## 5. Key trade-offs

| Decision | Why | Cost |
|---|---|---|
| Whole-file in memory | Simplicity; typical documents are MBs | Not suited to multi-GB files |
| Own PDF parser instead of poppler/mupdf | Zero install, user controls the code | No rendering, no encryption, no LZW/JBIG2 |
| Incremental updates, never a full rewrite | Safety and simplicity; standard-compliant | Files grow with every edit (no garbage collection) |
| Handler inheritance chain | Markdown gets all text/byte commands for free | Deep class chain; a flat capability registry would scale better past ~6 types |
| EPUB save rewrites the archive, copying unchanged entries | A zip has no append-and-supersede form that readers accept | Cost grows with book size (98 ms for a 24 MiB book) |
| Splice edits by byte offset instead of rebuilding XML | Leaves every byte the user did not touch as the publisher wrote it | Text split across tags cannot be matched |
| Heuristic line/word breaks in text extraction | No font metrics needed | Columns and tables flatten; justified text may gain spaces |

## 6. Known limits
- Encrypted PDFs: detected and reported; text is not decrypted and modification is refused.
- `replace` on PDFs only matches text that sits in one string operand of a simple font; text set
  in subset/CID fonts or split per glyph cannot be matched.
- `add-page` uses the base-14 Helvetica font, so non-WinAnsi characters will not render.
- Markdown rendering is a terminal approximation (ANSI), not a CommonMark implementation.
- EPUB: text only (no images, styling or footnote links); DRM-protected, Zip64 and UTF-16 books
  are refused with an error. `replace` cannot match text that crosses a tag or a source line break.
  Saving rewrites the whole archive, so it costs time in proportion to the book's size.

## 7. Extending
Add a type by subclassing `ByteHandler` (or `TextHandler`), implementing `commands()` and `run()`,
and adding one detection branch in `src/core/registry.cpp`. Add the file to `CMakeLists.txt`.
To change the Blender diagram, edit `LAYERS`, `COMPONENTS`, `EDGES` at the top of the script.
