// The app: a library of covers, and one file open for reading. Everything runs in the browser —
// the C++ engine as WebAssembly, the library in IndexedDB — so the page works with no network
// once it has been opened once.
import * as cover from "./cover.js";
import * as doc from "./document.js";
import * as engine from "./engine.js";
import * as store from "./store.js";
import { Reader, download, el, formatDate, panel } from "./reader.js";

const bar = document.querySelector("header.bar");
const main = document.querySelector("main");

let entries = [];
let shelf = null;         // the shelf being shown, or null for everything
let reader = null;
let sort = "opened";

start();

async function start() {
  await engine.load();
  await refresh();
  watchDrops();
  registerServiceWorker();
}

async function refresh() {
  entries = await store.entries();
  if (!reader) drawLibrary();
}

// ---------------------------------------------------------------- the library

function drawLibrary() {
  drawBar();
  main.innerHTML = "";
  const shown = visible();

  if (entries.length === 0) {
    main.append(welcome());
    return;
  }

  const grid = el("div", { class: "shelf" });
  for (const entry of shown) grid.append(drawBook(entry));
  main.append(grid);
}

function visible() {
  let shown = entries;
  if (shelf === "unfinished") shown = shown.filter((e) => !e.finished && e.position > 0 && !isDone(e));
  else if (shelf === "finished") shown = shown.filter(isDone);
  else if (shelf) shown = shown.filter((e) => (e.shelves || []).includes(shelf));

  const by = {
    opened: (a, b) => (b.opened || "").localeCompare(a.opened || ""),
    title: (a, b) => a.path.localeCompare(b.path),
    kind: (a, b) => a.kind.localeCompare(b.kind) || a.path.localeCompare(b.path),
  };
  return [...shown].sort(by[sort] || by.opened);
}

function isDone(entry) {
  if (entry.finished !== undefined && entry.finished !== null) return entry.finished;
  return progress(entry) >= 1;
}

function progress(entry) {
  if (!entry.position || !entry.total) return 0;
  return Math.min(1, entry.position / entry.total);
}

function drawBook(entry) {
  const book = el("div", { class: "book", tabindex: "0", role: "button" });
  const face = el("div", { class: "cover" });
  // The art is a layer of its own: it is drawn later, when the card reaches the screen, and
  // must not wipe the badge and the progress bar sitting over it.
  const art = el("div", { class: "art" });
  face.append(art);
  book.append(face);

  const name = el("div", { class: "name" }, entry.path);
  const note = el("div", { class: "note" }, describe(entry));
  book.append(name, note);

  // The cover is made from the file's own contents, which means reading the file; do it when
  // the card is on screen rather than for the whole library at once.
  watchOnce(face, async () => {
    const bytes = await store.fileBytes(entry.path);
    if (!bytes) { art.classList.add("leaf", "plain"); art.append(el("div", { class: "line" }, "file missing")); return; }
    drawCover(art, cover.art(bytes, entry.path, entry.kind));
    const named = cover.caption(bytes, entry.path, entry.kind);
    if (named.title) name.textContent = named.title;
    if (named.author) note.textContent = [named.author, describe(entry)].filter(Boolean).join(" · ");
  });

  if (entry.unopened) face.append(el("span", { class: "badge" }, "New"));
  else if (isDone(entry)) face.append(el("span", { class: "badge finished" }, "Read"));
  const through = progress(entry);
  if (through > 0 && !isDone(entry)) {
    const bar = el("div", { class: "progress" });
    bar.append(el("span", { style: `width: ${Math.round(through * 100)}%` }));
    face.append(bar);
  }

  book.onclick = () => openBook(entry);
  book.onkeydown = (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openBook(entry); } };
  book.oncontextmenu = (e) => { e.preventDefault(); bookMenu(entry); };
  return book;
}

function drawCover(face, art) {
  face.className = "art";
  face.innerHTML = "";
  switch (art.type) {
    case "picture":
      face.append(el("img", { src: art.url, alt: art.title, loading: "lazy" }));
      break;
    case "book": {
      face.classList.add("cloth");
      face.style.background = cover.CLOTHS[art.cloth];
      face.append(el("div", { class: "title" }, art.title.join("\n")));
      face.append(el("div", { class: "author" }, art.author));
      break;
    }
    case "note":
      face.classList.add("leaf");
      face.append(el("div", { class: "heading" }, art.heading));
      for (const row of art.rows) face.append(el("div", { class: "line" }, row));
      break;
    case "page":
      face.classList.add("leaf");
      for (const row of art.rows) face.append(el("div", { class: "line" }, row));
      break;
    case "text":
      face.classList.add("leaf", "plain");
      for (const row of art.rows) face.append(el("div", { class: "line" }, row));
      break;
    default:
      face.append(byteMap(art));
  }
}

/** A binary's bytes as a grid of coloured cells, the colours of Theme.bytes. */
function byteMap(art) {
  const colours = ["#0E1330", "#3B49DF", "#27B5A6", "#F2C14E", "#F5F4F0"];
  const canvas = el("canvas", { width: String(art.cols), height: String(art.rows) });
  const context = canvas.getContext("2d");
  context.fillStyle = colours[0];
  context.fillRect(0, 0, art.cols, art.rows);
  for (let i = 0; i < art.cells.length; i++) {
    context.fillStyle = colours[art.cells[i]] || colours[0];
    context.fillRect(i % art.cols, Math.floor(i / art.cols), 1, 1);
  }
  canvas.style.imageRendering = "pixelated";
  return canvas;
}

function describe(entry) {
  if (entry.unopened) return kindName(entry.kind);
  if (isDone(entry)) return "Finished";
  if (entry.position && entry.total) {
    const where = entry.kind === "pdf" ? `Page ${entry.position}` : `Chapter ${entry.position}`;
    return `${where} of ${entry.total}`;
  }
  if (entry.opened) return `Opened ${formatDate(entry.opened)}`;
  return kindName(entry.kind);
}

function kindName(kind) {
  return { epub: "Book", pdf: "PDF", markdown: "Note", text: "Text", binary: "File" }[kind] || kind;
}

/** Reads the file's bytes only when its card reaches the screen. */
function watchOnce(node, work) {
  const observer = new IntersectionObserver((rows) => {
    for (const row of rows) {
      if (row.isIntersecting) { observer.disconnect(); work(); }
    }
  }, { rootMargin: "200px" });
  observer.observe(node);
}

function welcome() {
  const box = el("div", { class: "empty" });
  box.append(el("h2", {}, "Your library is empty"));
  box.append(el("p", {}, "Add an EPUB, a PDF, a Markdown note, a text file — or anything else, which gets a hex view."));
  const add = el("button", { class: "primary" }, "Add files");
  add.onclick = pickFiles;
  box.append(add);
  box.append(el("p", { class: "hint", style: "margin-top:18px" }, "Everything stays on this device. Nothing is uploaded."));
  return box;
}

// ---------------------------------------------------------------- the bar

function drawBar() {
  bar.innerHTML = "";
  bar.append(el("h1", {}, "GranthFlow"));

  const shelves = new Set(entries.flatMap((e) => e.shelves || []));
  const select = el("select", { "aria-label": "Shelf" });
  const options = [["", "All"], ["unfinished", "Reading"], ["finished", "Finished"], ...[...shelves].sort().map((s) => [s, s])];
  for (const [value, label] of options) {
    const option = el("option", { value }, label);
    if ((shelf || "") === value) option.setAttribute("selected", "selected");
    select.append(option);
  }
  select.onchange = () => { shelf = select.value || null; drawLibrary(); };

  const sortSelect = el("select", { "aria-label": "Sort" });
  for (const [value, label] of [["opened", "Last opened"], ["title", "Name"], ["kind", "Kind"]]) {
    const option = el("option", { value }, label);
    if (sort === value) option.setAttribute("selected", "selected");
    sortSelect.append(option);
  }
  sortSelect.onchange = () => { sort = sortSelect.value; drawLibrary(); };

  const add = el("button", { class: "primary" }, "Add files");
  add.onclick = pickFiles;

  const marks = el("button", {}, "Marks");
  marks.onclick = showAllMarks;

  const move = el("button", { title: "Move a library between this and the Mac app" }, "Library");
  move.onclick = showLibraryPanel;

  bar.append(select, sortSelect, el("span", { class: "spacer" }),
             el("span", { class: "count" }, `${visible().length} of ${entries.length}`), marks, move, add);

  if (installPrompt) {
    const install = el("button", {}, "Install");
    install.onclick = async () => { installPrompt.prompt(); installPrompt = null; drawBar(); };
    bar.append(install);
  }
}

// ---------------------------------------------------------------- adding files

function pickFiles() {
  const input = el("input", { type: "file", multiple: "multiple", style: "display:none" });
  input.onchange = async () => {
    await addFiles([...input.files]);
    input.remove();
  };
  document.body.append(input);
  input.click();
}

async function addFiles(files) {
  let added = 0;
  for (const file of files) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    const kind = engine.detectKind(bytes, file.name);
    await store.addFile({ name: file.name, bytes, kind });
    added++;
  }
  await refresh();
  if (added) toast(added === 1 ? "Added 1 file" : `Added ${added} files`);
}

/** The whole window is a drop target, as the Mac app's library is. */
function watchDrops() {
  let depth = 0;
  window.addEventListener("dragenter", (e) => { e.preventDefault(); if (++depth === 1) document.body.classList.add("dropping"); });
  window.addEventListener("dragover", (e) => e.preventDefault());
  window.addEventListener("dragleave", () => { if (--depth <= 0) { depth = 0; document.body.classList.remove("dropping"); } });
  window.addEventListener("drop", async (e) => {
    e.preventDefault();
    depth = 0;
    document.body.classList.remove("dropping");
    const files = [...(e.dataTransfer?.files || [])];
    if (files.length) await addFiles(files);
  });
}

// ---------------------------------------------------------------- reading

async function openBook(entry) {
  const bytes = await store.fileBytes(entry.path);
  if (!bytes) { toast("That file's contents are not on this device"); return; }
  await store.noteReadingPlace(entry.path, {});
  main.innerHTML = "";
  bar.innerHTML = "";
  // What the book calls itself, as the shelf shows it, rather than the file name.
  bar.append(el("h1", {}, cover.caption(bytes, entry.path, entry.kind).title || entry.path));
  reader = new Reader({
    root: main,
    entry: await store.entry(entry.path),
    bytes,
    toast,
    onChanged: () => { store.entries().then((rows) => { entries = rows; }); },
    onClose: async () => { reader = null; await refresh(); window.scrollTo({ top: 0 }); },
  });
  await reader.open();
}

function bookMenu(entry) {
  const body = el("div", { class: "body" });

  const shelfField = el("div", { class: "field" });
  shelfField.append(el("label", {}, "Shelves — separated by commas"));
  const shelves = el("input", { type: "text", value: (entry.shelves || []).join(", "), placeholder: "Poetry, To read" });
  shelfField.append(shelves);
  body.append(shelfField);
  body.append(el("p", { class: "hint" }, `${kindName(entry.kind)} · ${describe(entry)}`));

  const save = el("button", { class: "primary" }, "Save");
  save.onclick = async () => {
    const list = shelves.value.split(",").map((s) => s.trim()).filter(Boolean);
    await store.setShelves(entry.path, list.length ? list : undefined);
    dialog.close();
    await refresh();
  };
  const remove = el("button", {}, "Remove from library");
  remove.onclick = async () => {
    if (!confirm(`Remove ${entry.path} and its marks from this device?`)) return;
    await store.removeFile(entry.path);
    dialog.close();
    await refresh();
    toast("Removed");
  };
  const save2 = el("button", {}, "Save a copy");
  save2.onclick = async () => {
    const bytes = await store.fileBytes(entry.path);
    if (bytes) download(entry.path, bytes, "application/octet-stream");
  };
  const dialog = panel(entry.path, body, [save2, remove, save]);
}

// ---------------------------------------------------------------- marks across the library

async function showAllMarks() {
  const all = await store.marks();
  const body = el("div", { class: "body" });
  if (all.length === 0) body.append(el("p", { class: "hint" }, "No marks yet. Select a passage while reading to mark it."));

  const search = el("input", { type: "search", placeholder: "Search marks and notes" });
  const list = el("div", {});
  const draw = () => {
    const term = search.value.trim().toLowerCase();
    list.innerHTML = "";
    const shown = term ? all.filter((m) => (m.quote + " " + (m.note || "")).toLowerCase().includes(term)) : all;
    for (const mark of shown) {
      const row = el("div", { class: `mark-row ${mark.colour}` });
      row.append(el("blockquote", {}, mark.quote));
      if (mark.note) row.append(el("p", { class: "note" }, mark.note));
      row.append(el("div", { class: "where" }, [mark.path, mark.place, formatDate(mark.created)].filter(Boolean).join(" · ")));
      row.onclick = async () => {
        const entry = entries.find((e) => e.path === mark.path);
        if (!entry) return;
        dialog.close();
        await openBook(entry);
        if (mark.target) reader?.goTo(mark.target);
      };
      list.append(row);
    }
    if (shown.length === 0 && term) list.append(el("p", { class: "hint" }, "Nothing found."));
  };
  search.oninput = draw;
  if (all.length) { body.append(el("div", { class: "field" }, search)); body.append(list); draw(); }

  const exportAll = el("button", {}, "Export all as Markdown");
  exportAll.onclick = () => {
    const lines = ["# Marks", ""];
    const byBook = new Map();
    for (const mark of [...all].reverse()) {
      if (!byBook.has(mark.path)) byBook.set(mark.path, []);
      byBook.get(mark.path).push(mark);
    }
    for (const [path, rows] of byBook) {
      lines.push(`## ${path}`, "");
      for (const mark of rows) {
        lines.push(`> ${mark.quote.replace(/\n/g, "\n> ")}`, "");
        if (mark.note) lines.push(mark.note, "");
        lines.push(`— ${[mark.place, formatDate(mark.created)].filter(Boolean).join(", ")}`, "");
      }
    }
    download("marks.md", lines.join("\n"), "text/markdown");
  };
  const dialog = panel("Marks", body, all.length ? [exportAll] : []);
}

// ---------------------------------------------------------------- moving a library

async function showLibraryPanel() {
  const body = el("div", { class: "body" });
  body.append(el("p", { class: "hint" },
    "The Mac app keeps its library in ~/Library/Application Support/Anyfile/ as library.json and marks.json. " +
    "These are the same two files, so a library moves either way."));

  const room = await store.usage();
  if (room) {
    body.append(el("p", { class: "hint", style: "margin-top:10px" },
      `Using ${megabytes(room.used)} of about ${megabytes(room.quota)} available on this device.`));
  }

  const out = el("button", {}, "Export library.json + marks.json");
  out.onclick = async () => {
    const files = await store.exportLibrary();
    for (const [name, content] of Object.entries(files)) download(name, content, "application/json");
  };

  const inLabel = el("div", { class: "field", style: "margin-top:14px" });
  inLabel.append(el("label", {}, "Import"));
  const file = el("input", { type: "file", accept: ".json,application/json", multiple: "multiple" });
  file.onchange = async () => {
    const payload = { library: [], marks: [] };
    for (const chosen of file.files) {
      try {
        const rows = JSON.parse(await chosen.text());
        if (!Array.isArray(rows)) continue;
        // Marks carry a quote; library entries carry a kind. That tells the two files apart
        // whatever they have been renamed to.
        if (rows.length === 0) continue;
        if ("quote" in rows[0]) payload.marks.push(...rows);
        else payload.library.push(...rows);
      } catch {
        toast(`${chosen.name} is not JSON this understands`);
      }
    }
    const report = await store.importLibrary(payload);
    await refresh();
    dialog.close();
    toast(`Imported ${report.entries} entries and ${report.marks} marks`);
  };
  inLabel.append(file);
  inLabel.append(el("p", { class: "hint" }, "Pick library.json, marks.json, or both. Nothing already here is lost: the later reading place wins, and a mark is added only if its id is new."));
  body.append(inLabel);

  const dialog = panel("Library", body, [out]);
}

function megabytes(bytes) {
  if (!bytes) return "0 MB";
  return bytes > 1e9 ? `${(bytes / 1e9).toFixed(1)} GB` : `${Math.round(bytes / 1e6)} MB`;
}

// ---------------------------------------------------------------- the page itself

let installPrompt = null;
window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  installPrompt = e;
  if (!reader) drawBar();
});

function registerServiceWorker() {
  // The page is served from web/, so the worker's scope is this folder.
  if ("serviceWorker" in navigator) navigator.serviceWorker.register("./sw.js").catch(() => {});
}

/** Files opened from the system, when the browser supports it: "Open with GranthFlow". */
if ("launchQueue" in window) {
  launchQueue.setConsumer(async (params) => {
    if (!params.files?.length) return;
    await engine.load();
    const files = await Promise.all(params.files.map((handle) => handle.getFile()));
    await addFiles(files);
  });
}

function toast(message) {
  const node = el("div", { class: "toast" }, message);
  document.body.append(node);
  setTimeout(() => node.remove(), 2600);
}
