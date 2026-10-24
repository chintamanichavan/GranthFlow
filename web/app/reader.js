// One file, open for reading. EPUB chapters and PDF pages turn one at a time; Markdown and text
// are one long column; anything else gets a hex view. Marks are painted over the text, and the
// reading place is written back to the library as it moves, as mac/Anyfile/Views/ContentView.swift does.
import * as doc from "./document.js";
import * as store from "./store.js";

const COLOURS = ["yellow", "pink", "green", "blue"];

/** Text size, spacing, column width and look — the fields of ReadingSettings. */
const DEFAULT_SETTINGS = { size: 17, spacing: "normal", width: "normal", look: "auto" };
const LEADING = { tight: 1.25, normal: 1.45, loose: 1.7 };
const MEASURE = { narrow: 460, normal: 560, wide: 700 };

export class Reader {
  constructor({ root, entry, bytes, onClose, onChanged, toast }) {
    this.root = root;
    this.entry = entry;
    this.bytes = bytes;
    this.onClose = onClose;
    this.onChanged = onChanged;
    this.toast = toast;
    this.kind = entry.kind;
    this.name = entry.path;
    this.settings = { ...DEFAULT_SETTINGS, ...(entry.settings || {}) };
    this.contents = doc.contents(this.bytes, this.name, this.kind);
    this.total = this.contents.length;
    this.position = clamp(entry.position ?? 1, 1, Math.max(1, this.total));
    this.hexOffset = 0;
    this.marks = [];
  }

  async open() {
    this.marks = await store.marksFor(this.entry.path);
    document.body.classList.add("reading");
    this.applyLook();
    this.draw();
    this.keys = (e) => this.onKey(e);
    window.addEventListener("keydown", this.keys);
  }

  close() {
    window.removeEventListener("keydown", this.keys);
    document.body.classList.remove("reading", "look-paper", "look-sepia", "look-night");
    this.onClose();
  }

  applyLook() {
    document.body.classList.remove("look-paper", "look-sepia", "look-night");
    if (this.settings.look !== "auto") document.body.classList.add(`look-${this.settings.look}`);
    this.root.style.setProperty("--size", `${this.settings.size}px`);
    this.root.style.setProperty("--leading", LEADING[this.settings.spacing]);
    // The measure grows with the text so a line keeps about the same number of words.
    this.root.style.setProperty("--measure", `${MEASURE[this.settings.width] * this.settings.size / 17}px`);
  }

  // ---------------------------------------------------------------- drawing

  draw() {
    this.root.innerHTML = "";
    const hasContents = this.contents.length > 0;
    const layout = el("div", { class: `reader${hasContents ? "" : " alone"}` });
    if (hasContents) layout.append(this.drawContents());
    layout.append(this.drawPage());
    this.root.append(layout, this.drawActions());
    if (this.pageText) this.watchSelection();
  }

  drawContents() {
    const panel = el("div", { class: "contents" });
    panel.append(el("h2", {}, this.kind === "pdf" ? "Pages" : this.kind === "markdown" ? "Outline" : "Contents"));
    for (const item of this.contents) {
      const link = el("a", {
        href: "#",
        "aria-current": String(item.index === this.position),
        style: item.level ? `padding-left: ${18 + (item.level - 1) * 12}px` : "",
      });
      // A heading in a note is a place in one column, so it scrolls; a chapter or page is turned to.
      if (!item.level) link.append(el("span", { class: "where" }, String(item.index)));
      link.append(document.createTextNode(item.title));
      link.onclick = (e) => {
        e.preventDefault();
        if (item.level) this.scrollToHeading(item);
        else this.goTo(item.index);
      };
      panel.append(link);
    }
    return panel;
  }

  drawPage() {
    const page = el("div", { class: "page" });

    if (this.kind === "binary") {
      page.append(el("pre", { class: "column mono" }, doc.hex(this.bytes, this.name, this.hexOffset)));
      page.append(this.drawHexTurn());
      return page;
    }

    const text = doc.textAt(this.bytes, this.name, this.kind, this.position);
    this.pageText = text;
    const column = el("div", { class: "column" });
    this.paint(column, text);
    page.append(column);
    this.column = column;

    if (this.total > 1) page.append(this.drawTurn());
    else if (this.kind === "markdown" || this.kind === "text") page.append(this.drawTimeLeft(text));
    return page;
  }

  /** The text with every mark on this page painted over it. */
  paint(column, text) {
    const here = this.marks
      .filter((m) => this.total <= 1 || m.target === this.position)
      .map((m) => ({ mark: m, at: text.indexOf(m.quote) }))
      .filter((m) => m.at >= 0)
      .sort((a, b) => a.at - b.at);

    let cursor = 0;
    for (const { mark, at } of here) {
      if (at < cursor) continue;                       // overlapping marks: the first one wins
      column.append(document.createTextNode(text.slice(cursor, at)));
      const painted = el("mark", { class: mark.colour, title: mark.note || "" }, mark.quote);
      painted.onclick = () => this.editMark(mark);
      column.append(painted);
      cursor = at + mark.quote.length;
    }
    column.append(document.createTextNode(text.slice(cursor)));
  }

  drawTurn() {
    const turn = el("div", { class: "turn" });
    const back = el("button", {}, "‹ Back");
    const next = el("button", {}, "Next ›");
    back.disabled = this.position <= 1;
    next.disabled = this.position >= this.total;
    back.onclick = () => this.goTo(this.position - 1);
    next.onclick = () => this.goTo(this.position + 1);
    const where = el("span", { class: "left" }, this.progressText());
    turn.append(back, where, next);
    return turn;
  }

  drawHexTurn() {
    const turn = el("div", { class: "turn" });
    const back = el("button", {}, "‹ Back");
    const next = el("button", {}, "Next ›");
    back.disabled = this.hexOffset === 0;
    next.disabled = this.hexOffset + 2048 >= this.bytes.length;
    back.onclick = () => { this.hexOffset = Math.max(0, this.hexOffset - 2048); this.draw(); };
    next.onclick = () => { this.hexOffset += 2048; this.draw(); };
    turn.append(back, el("span", { class: "left" }, `${this.hexOffset} of ${this.bytes.length} bytes`), next);
    return turn;
  }

  drawTimeLeft(text) {
    const words = doc.wordsFrom(text, 0);
    const minutes = Math.max(1, Math.round(words / 240));   // 240 words a minute, as ReadingTime uses
    return el("div", { class: "left" }, `${words.toLocaleString()} words · about ${minutes} min`);
  }

  progressText() {
    if (this.kind === "epub") return `Chapter ${this.position} of ${this.total}`;
    if (this.kind === "pdf") return `Page ${this.position} of ${this.total}`;
    return "";
  }

  drawActions() {
    const bar = el("div", { class: "actions" });
    const back = el("button", { class: "plain" }, "‹ Library");
    back.onclick = () => this.close();

    const marksButton = el("button", {}, `Marks${this.marks.length ? ` (${this.marks.length})` : ""}`);
    marksButton.onclick = () => this.showMarks();

    const type = el("button", { title: "Text size, spacing, width and look" }, "Aa");
    type.onclick = () => this.showTypeSettings();

    const finish = el("button", { "aria-pressed": String(!!this.entry.finished) }, "Finished");
    finish.onclick = async () => {
      this.entry.finished = !this.entry.finished;
      await store.setFinished(this.entry.path, this.entry.finished);
      this.onChanged?.();
      this.draw();
    };

    bar.append(back, marksButton, type, finish);
    if (this.kind !== "binary") {
      const speak = el("button", { "aria-pressed": String(speaking()) }, speaking() ? "Stop" : "Read aloud");
      speak.onclick = () => { this.readAloud(); this.draw(); };
      bar.append(speak);
    }
    return bar;
  }

  // ---------------------------------------------------------------- moving

  async goTo(position) {
    this.position = clamp(position, 1, Math.max(1, this.total));
    const text = doc.textAt(this.bytes, this.name, this.kind, this.position);
    await store.noteReadingPlace(this.entry.path, {
      position: this.position,
      total: this.total,
      wordsLeft: doc.wordsFrom(text, 0),
    });
    this.onChanged?.();
    this.draw();
    window.scrollTo({ top: 0 });
  }

  scrollToHeading(item) {
    // The outline gives a line number; count newlines to find it in the column.
    const text = this.pageText || "";
    const upto = text.split("\n").slice(0, Math.max(0, item.line - 1)).join("\n").length;
    const ratio = text.length ? upto / text.length : 0;
    window.scrollTo({ top: this.column.offsetTop + this.column.scrollHeight * ratio - 70, behavior: "smooth" });
  }

  onKey(e) {
    if (e.target.matches("input, textarea") || document.querySelector("dialog[open]")) return;
    if (e.key === "ArrowRight" || e.key === " ") { e.preventDefault(); this.goTo(this.position + 1); }
    if (e.key === "ArrowLeft") { e.preventDefault(); this.goTo(this.position - 1); }
    if (e.key === "Escape") this.close();
  }

  // ---------------------------------------------------------------- marking

  /** The colour buttons appear wherever a passage is selected. */
  watchSelection() {
    const show = () => {
      this.marker?.remove();
      this.marker = null;
      const selection = window.getSelection();
      if (!selection || selection.isCollapsed) return;
      const quote = selection.toString().trim();
      if (quote.length < 2 || !this.column?.contains(selection.anchorNode)) return;

      const box = selection.getRangeAt(0).getBoundingClientRect();
      const marker = el("div", { class: "marker" });
      for (const colour of COLOURS) {
        const button = el("button", { class: colour, title: colour[0].toUpperCase() + colour.slice(1) });
        button.onclick = async () => {
          await this.addMark(quote, colour);
          selection.removeAllRanges();
        };
        marker.append(button);
      }
      marker.style.left = `${Math.max(8, box.left + window.scrollX)}px`;
      marker.style.top = `${box.top + window.scrollY - 44}px`;
      document.body.append(marker);
      this.marker = marker;
    };
    document.addEventListener("selectionchange", () => setTimeout(show, 10));
  }

  async addMark(quote, colour) {
    const mark = await store.addMark({
      path: this.entry.path,
      kind: this.kind,
      quote,
      target: this.total > 1 ? this.position : 0,
      place: this.placeName(),
      colour,
    });
    this.marks.unshift(mark);
    this.onChanged?.();
    this.draw();
    this.toast?.("Marked");
  }

  placeName() {
    if (this.kind === "epub") return `Chapter ${this.position}`;
    if (this.kind === "pdf") return `Page ${this.position}`;
    return "";
  }

  // ---------------------------------------------------------------- panels

  showMarks() {
    const body = el("div", { class: "body" });
    if (this.marks.length === 0) {
      body.append(el("p", { class: "hint" }, "Select a passage in the text to mark it."));
    }
    for (const mark of this.marks) {
      const row = el("div", { class: `mark-row ${mark.colour}` });
      row.append(el("blockquote", {}, mark.quote));
      if (mark.note) row.append(el("p", { class: "note" }, mark.note));
      const where = el("div", { class: "row" });
      where.append(el("span", { class: "where" }, [mark.place, formatDate(mark.created)].filter(Boolean).join(" · ")));
      where.append(el("span", { class: "spacer", style: "flex:1" }));
      if (mark.target) {
        const go = el("button", { class: "plain" }, "Open");
        go.onclick = () => { dialog.close(); this.goTo(mark.target); };
        where.append(go);
      }
      const edit = el("button", { class: "plain" }, "Note");
      edit.onclick = () => { dialog.close(); this.editMark(mark); };
      const remove = el("button", { class: "plain" }, "Remove");
      remove.onclick = async () => {
        await store.removeMark(mark.id);
        this.marks = this.marks.filter((m) => m.id !== mark.id);
        dialog.close();
        this.onChanged?.();
        this.draw();
      };
      where.append(edit, remove);
      row.append(where);
      body.append(row);
    }

    const exportButton = el("button", {}, "Export as Markdown");
    exportButton.onclick = () => this.exportMarks();
    const dialog = panel(`Marks in ${this.entry.path}`, body, [exportButton]);
  }

  editMark(mark) {
    const body = el("div", { class: "body" });
    body.append(el("blockquote", { style: "margin:0 0 12px; padding-left:10px; border-left:3px solid var(--mark); font:14px/1.45 var(--serif)" }, mark.quote));
    const field = el("div", { class: "field" });
    field.append(el("label", { for: "mark-note" }, "Note"));
    const note = el("textarea", { id: "mark-note", placeholder: "Your own words about the passage" });
    note.value = mark.note || "";
    field.append(note);
    body.append(field);

    const colours = el("div", { class: "row" });
    for (const colour of COLOURS) {
      const button = el("button", { class: colour, "aria-pressed": String(mark.colour === colour), style: `background: var(--mark${colour === "yellow" ? "" : "-" + colour}); width:24px; height:24px; padding:0; border-radius:50%` });
      button.onclick = () => {
        mark.colour = colour;
        for (const other of colours.children) other.setAttribute("aria-pressed", "false");
        button.setAttribute("aria-pressed", "true");
      };
      colours.append(button);
    }
    body.append(colours);

    const save = el("button", { class: "primary" }, "Save");
    save.onclick = async () => {
      const updated = await store.updateMark(mark.id, { note: note.value, colour: mark.colour });
      this.marks = this.marks.map((m) => (m.id === mark.id ? updated : m));
      dialog.close();
      this.onChanged?.();
      this.draw();
    };
    const dialog = panel("Mark", body, [save]);
  }

  showTypeSettings() {
    const body = el("div", { class: "body" });

    const sizeRow = el("div", { class: "field" });
    sizeRow.append(el("label", {}, `Text size — ${this.settings.size}pt`));
    const size = el("input", { type: "range", min: "13", max: "28", step: "1", value: String(this.settings.size) });
    size.oninput = () => {
      this.settings.size = Number(size.value);
      sizeRow.firstChild.textContent = `Text size — ${this.settings.size}pt`;
      this.saveSettings();
    };
    sizeRow.append(size);
    body.append(sizeRow);

    body.append(this.choices("Spacing", "spacing", ["tight", "normal", "loose"]));
    body.append(this.choices("Column width", "width", ["narrow", "normal", "wide"]));
    body.append(this.choices("Look", "look", ["auto", "paper", "sepia", "night"]));

    panel("Reading", body, []);
  }

  choices(label, key, options) {
    const field = el("div", { class: "field" });
    field.append(el("label", {}, label));
    const row = el("div", { class: "row" });
    for (const option of options) {
      const button = el("button", { "aria-pressed": String(this.settings[key] === option) }, option[0].toUpperCase() + option.slice(1));
      button.onclick = () => {
        this.settings[key] = option;
        for (const other of row.children) other.setAttribute("aria-pressed", "false");
        button.setAttribute("aria-pressed", "true");
        this.saveSettings();
      };
      row.append(button);
    }
    field.append(row);
    return field;
  }

  async saveSettings() {
    this.applyLook();
    await store.setSettings(this.entry.path, this.settings);
  }

  exportMarks() {
    // The same shape mac/Anyfile/MarkExport.swift writes.
    const lines = [`# Marks in ${this.entry.path}`, ""];
    for (const mark of [...this.marks].reverse()) {
      lines.push(`> ${mark.quote.replace(/\n/g, "\n> ")}`);
      lines.push("");
      if (mark.note) lines.push(mark.note, "");
      lines.push(`— ${[mark.place, formatDate(mark.created)].filter(Boolean).join(", ")}`, "");
    }
    download(`${this.entry.path}.marks.md`, lines.join("\n"), "text/markdown");
  }

  /** Reads the page aloud, the spoken sentence underlined, using the browser's own voice. */
  readAloud() {
    if (speaking()) { speechSynthesis.cancel(); return; }
    const text = this.pageText || "";
    if (!text.trim()) return;
    const utterance = new SpeechSynthesisUtterance(text.slice(0, 32000));
    utterance.rate = 1;
    utterance.onend = () => this.draw();
    speechSynthesis.speak(utterance);
  }
}

function speaking() {
  return typeof speechSynthesis !== "undefined" && (speechSynthesis.speaking || speechSynthesis.pending);
}

// ---------------------------------------------------------------- small helpers

export function el(tag, attributes = {}, children = null) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (value !== "" && value !== null && value !== undefined) node.setAttribute(key, value);
  }
  if (typeof children === "string") node.textContent = children;
  else if (Array.isArray(children)) node.append(...children);
  else if (children) node.append(children);
  return node;
}

/** A modal that removes itself when it closes, so panels never pile up in the document. */
export function panel(title, body, buttons) {
  const dialog = el("dialog");
  const head = el("div", { class: "head" });
  head.append(el("h2", {}, title));
  const close = el("button", { class: "plain" }, "Close");
  close.onclick = () => dialog.close();
  head.append(close);
  const foot = el("div", { class: "foot" }, buttons);
  dialog.append(head, body, foot);
  dialog.addEventListener("close", () => dialog.remove());
  document.body.append(dialog);
  dialog.showModal();
  return dialog;
}

export function download(name, content, type) {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = el("a", { href: url, download: name });
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function formatDate(iso) {
  if (!iso) return "";
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
}

function clamp(value, low, high) {
  return Math.min(high, Math.max(low, value));
}
