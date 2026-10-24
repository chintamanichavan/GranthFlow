// Every file has a face. A cover is made from the file's own contents: a book's own cover
// picture (or its title and author on cloth when it has none), a note's first lines, a page's
// opening text, or, for a program, a map of its bytes.
//
// The counterpart of mac/Anyfile/Cover.swift. The cloths and the ink are the same colours, so a
// book that is deep blue on the Mac is deep blue here.
import { contents, fileInside, filesInside, info, meta, textAt } from "./document.js";

/** Book cloths: deep colours that light ink reads well on. The first is Moby-Dick's in the design. */
export const CLOTHS = ["#1B2F63", "#6E1E24", "#1F4A3A", "#7A4E16", "#4A2A5E", "#2E3A48"];
export const INK = "#F1E4C6";
export const MAP_COLS = 30;
export const MAP_ROWS = 42;

/**
 * What to draw for a file.
 * @returns {{type: string} & Record<string, unknown>}
 *   book    {title: string[], author, cloth}   a title on cloth
 *   picture {url, title, author}               the book's own cover
 *   page    {rows, title}                      a PDF's opening lines
 *   note    {heading, rows}                    a Markdown note
 *   text    {rows}                             a text file's first lines
 *   bytes   {cells, cols, rows}                a map of a binary's bytes
 */
export function art(bytes, name, kind) {
  switch (kind) {
    case "epub": {
      const fields = meta(bytes, name, kind);
      const title = fields.title || stem(name);
      const author = fields.creator || fields.author || "";
      const picture = bookCover(bytes, name);
      if (picture) return { type: "picture", url: picture, title, author };
      return { type: "book", title: titleLines(title), author, cloth: stableHash(title) % CLOTHS.length };
    }
    case "pdf": {
      // No page is rasterised here: the engine reads text, not images, so the opening lines
      // stand in for the thumbnail the Mac app gets from PDFKit.
      const fields = meta(bytes, name, kind);
      const opening = textAt(bytes, name, kind, 1)
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .slice(0, 9);
      return { type: "page", rows: opening, title: fields.title || stem(name) };
    }
    case "markdown": {
      const headings = contents(bytes, name, kind);
      const heading = headings.find((h) => h.level === 1)?.title || headings[0]?.title || stem(name);
      const rows = textAt(bytes, name, kind)
        .split("\n")
        .map((line) => line.replace(/^#+\s*/, "").trim())
        .filter((line) => line.length > 0 && line !== heading)
        .slice(0, 8);
      return { type: "note", heading, rows };
    }
    case "text": {
      const rows = textAt(bytes, name, kind)
        .split("\n")
        .slice(0, 9)
        .map((line) => line.slice(0, 28));
      return { type: "text", rows };
    }
    default:
      return { type: "bytes", cells: byteMap(bytes), cols: MAP_COLS, rows: MAP_ROWS };
  }
}

/** A caption for the shelf: what the file calls itself, rather than its file name. */
export function caption(bytes, name, kind) {
  if (kind === "epub") {
    const fields = meta(bytes, name, kind);
    return { title: fields.title || stem(name), author: fields.creator || fields.author || "" };
  }
  if (kind === "pdf") return { title: meta(bytes, name, kind).title || stem(name), author: "" };
  if (kind === "markdown") return { title: info(bytes, name, kind).title || stem(name), author: "" };
  return { title: stem(name), author: "" };
}

/**
 * The book's own cover picture, as a blob URL, when the archive holds one. Looked for the way
 * readers name it, since the manifest's cover item is not always marked.
 */
function bookCover(bytes, name) {
  const images = filesInside(bytes, name).filter((f) => /\.(jpe?g|png|gif|webp)$/i.test(f.path));
  if (images.length === 0) return null;
  const named = images.find((f) => /cover/i.test(f.path));
  // Failing a name, the largest image in the first few entries is almost always the cover.
  const chosen = named || images.slice(0, 4).sort((a, b) => b.size - a.size)[0];
  const data = fileInside(bytes, name, chosen.path);
  if (!data || data.length === 0) return null;
  const type = /\.png$/i.test(chosen.path) ? "image/png"
    : /\.gif$/i.test(chosen.path) ? "image/gif"
    : /\.webp$/i.test(chosen.path) ? "image/webp" : "image/jpeg";
  return URL.createObjectURL(new Blob([data], { type }));
}

/** A title broken into lines that fit a cover, longest word first deciding the breaks. */
function titleLines(title, limit = 14) {
  const words = title.split(/\s+/).filter(Boolean);
  const rows = [];
  let current = "";
  for (const word of words) {
    if (current && (current + " " + word).length > limit) { rows.push(current); current = word; }
    else current = current ? current + " " + word : word;
  }
  if (current) rows.push(current);
  return rows.slice(0, 4);
}

/**
 * A binary's bytes as a grid: each cell is one of five bands — zero, text, low, high, 0xFF —
 * so a program, an image and a compressed archive each look like themselves.
 */
function byteMap(bytes) {
  const cells = new Uint8Array(MAP_COLS * MAP_ROWS);
  if (bytes.length === 0) return cells;
  const step = bytes.length / cells.length;
  for (let i = 0; i < cells.length; i++) {
    const byte = bytes[Math.min(bytes.length - 1, Math.floor(i * step))];
    cells[i] = byte === 0 ? 0
      : byte === 0xff ? 4
      : byte >= 0x20 && byte < 0x7f ? 1
      : byte < 0x20 ? 2 : 3;
  }
  return cells;
}

function stem(name) {
  const base = name.split("/").pop();
  const dot = base.lastIndexOf(".");
  return dot > 0 ? base.slice(0, dot) : base;
}

/** The same cloth for the same title on every device, so a book keeps its colour. */
function stableHash(text) {
  let hash = 5381;
  for (let i = 0; i < text.length; i++) hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0;
  return hash;
}
