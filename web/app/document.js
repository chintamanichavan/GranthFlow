// A file as something to read: its metadata, its contents list, and the text at one place.
// Every answer comes from the engine's own commands, so a chapter here is the chapter the Mac
// app and the CLI would show. The parsing below is of the commands' tab-separated output.
import { output, run } from "./engine.js";

/** `meta` prints "key: value" lines. */
export function meta(bytes, name, kind) {
  const result = {};
  for (const line of output("meta", [], bytes, name, kind).split("\n")) {
    const colon = line.indexOf(":");
    if (colon > 0) result[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
  }
  return result;
}

/** `info` prints "key: value" lines for every kind. */
export function info(bytes, name, kind) {
  const result = {};
  for (const line of output("info", [], bytes, name, kind).split("\n")) {
    const colon = line.indexOf(":");
    if (colon > 0) result[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
  }
  return result;
}

/**
 * What this file is divided into: EPUB chapters, PDF pages, Markdown headings. Text and binary
 * files have no divisions and give an empty list.
 * @returns {{index: number, title: string, level?: number, line?: number}[]}
 */
export function contents(bytes, name, kind) {
  switch (kind) {
    case "epub":
      // "1\tChapter 1\tOPS/c0.xhtml"
      return lines(output("chapters", [], bytes, name, kind)).map((line) => {
        const [number, title] = line.split("\t");
        return { index: Number(number), title: title || `Chapter ${number}` };
      });
    case "pdf":
      // "1\tobj 5\t612 x 792 pt"
      return lines(output("pages", [], bytes, name, kind)).map((line) => {
        const number = Number(line.split("\t")[0]);
        return { index: number, title: `Page ${number}` };
      });
    case "markdown": {
      // "5\t  Second" — the indent is two spaces per level below the top.
      return lines(output("outline", [], bytes, name, kind)).map((line, i) => {
        const tab = line.indexOf("\t");
        const heading = line.slice(tab + 1);
        const indent = heading.length - heading.trimStart().length;
        return { index: i + 1, title: heading.trim(), level: Math.floor(indent / 2) + 1, line: Number(line.slice(0, tab)) };
      });
    }
    default:
      return [];
  }
}

/** How many chapters or pages there are; 0 when the kind has no divisions. */
export function total(bytes, name, kind) {
  if (kind === "epub" || kind === "pdf") return contents(bytes, name, kind).length;
  return 0;
}

/**
 * The text at one place: a chapter for EPUB, a page for PDF, the whole thing otherwise.
 * `position` is 1-based for EPUB chapters and PDF pages, matching the engine and the Mac app.
 */
export function textAt(bytes, name, kind, position = 1) {
  switch (kind) {
    case "epub":
    case "pdf":
      return output("text", [String(position)], bytes, name, kind);
    case "markdown":
    case "text":
      return output("show", [], bytes, name, kind);
    default:
      return "";
  }
}

/** A window of the hex dump, for files with no text to read. */
export function hex(bytes, name, offset = 0, length = 2048) {
  return output("hex", [String(offset), String(length)], bytes, name, "binary");
}

/** The whole text of a file, for searching and for counting what is left to read. */
export function fullText(bytes, name, kind) {
  if (kind === "epub" || kind === "pdf") return output("text", [], bytes, name, kind);
  return output("show", [], bytes, name, kind);
}

/** Words from a point in the text to its end, for "6 min left in chapter". */
export function wordsFrom(text, anchor = 0) {
  const rest = text.slice(Math.max(0, anchor));
  const words = rest.match(/\S+/g);
  return words ? words.length : 0;
}

/** A file inside an EPUB, as bytes — used to lift a book's own cover picture out. */
export function fileInside(bytes, name, innerPath) {
  const result = run("cat", [innerPath], bytes, name, "epub");
  return result.succeeded ? result.outputData : null;
}

/** The archive's entries: "20\tmimetype". */
export function filesInside(bytes, name) {
  return lines(output("files", [], bytes, name, "epub")).map((line) => {
    const [size, path] = line.split("\t");
    return { size: Number(size), path };
  });
}

function lines(text) {
  return text.split("\n").filter((line) => line.length > 0);
}
