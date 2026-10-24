// What the library remembers, and the files themselves, in IndexedDB.
//
// The two records mirror the Mac app's files byte for byte in shape: `entries` holds what
// mac/Anyfile/Library.swift writes to library.json, `marks` what Marks.swift writes to
// marks.json. Keeping the schema identical is what lets a library move between the two
// (see exportLibrary / importLibrary) rather than being trapped in one of them.
//
// Two differences the browser forces, both additive so Swift's decoder ignores them:
//   `path`  on the Mac is an absolute filesystem path. A browser never learns one, so here it
//           is the file's name, which is also what the Mac app shows as the entry's name.
//   `hash`  a SHA-256 of the contents, because a name alone cannot tell two books apart on
//           import. The Mac app has the real path for that and ignores this field.

const DB_NAME = "granthflow";
const DB_VERSION = 1;

/** Dates must be ISO8601 *without* fractional seconds: Swift's .iso8601 strategy rejects ".000Z". */
export function isoNow(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** Uppercase, the way Swift's UUID encodes; Swift reads either case back. */
function uuid() {
  return crypto.randomUUID().toUpperCase();
}

export async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

let dbPromise = null;

function open() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      // Entries and marks are keyed the way the Mac app keys them: an entry by its path, a mark by its id.
      if (!db.objectStoreNames.contains("entries")) db.createObjectStore("entries", { keyPath: "path" });
      if (!db.objectStoreNames.contains("marks")) db.createObjectStore("marks", { keyPath: "id" });
      // The bytes live apart from the entry so the library can be listed without loading any book.
      if (!db.objectStoreNames.contains("files")) db.createObjectStore("files", { keyPath: "path" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return dbPromise;
}

async function tx(stores, mode, work) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(stores, mode);
    const result = work(...stores.map((s) => transaction.objectStore(s)));
    transaction.oncomplete = () => resolve(result instanceof Function ? result() : result);
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

function wrap(request) {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

// ---------------------------------------------------------------- the library

/** Every entry, newest opening first, the order the shelf is drawn in. */
export async function entries() {
  const all = await tx(["entries"], "readonly", (store) => wrap(store.getAll()));
  return (await all).sort((a, b) => (b.opened || "").localeCompare(a.opened || ""));
}

export async function entry(path) {
  return tx(["entries"], "readonly", (store) => wrap(store.get(path)));
}

export async function putEntry(record) {
  return tx(["entries"], "readwrite", (store) => wrap(store.put(record)));
}

/** The bytes of one file, or undefined when only the entry survived. */
export async function fileBytes(path) {
  const record = await tx(["files"], "readonly", (store) => wrap(store.get(path)));
  return (await record)?.bytes;
}

/**
 * Takes a file into the library. An entry already there keeps its reading place and marks,
 * so re-adding a book you are halfway through does not lose where you were.
 */
export async function addFile({ name, bytes, kind }) {
  const path = await uniquePath(name, bytes);
  const existing = await entry(path);
  const record = existing
    ? { ...existing, kind, unopened: existing.unopened ?? true }
    : { path, kind, opened: isoNow(), unopened: true, hash: await sha256(bytes) };
  await tx(["files", "entries"], "readwrite", (files, entriesStore) => {
    files.put({ path, bytes });
    entriesStore.put(record);
  });
  return record;
}

/**
 * The name to file it under. The same name holding the same bytes is the same book; the same
 * name holding different bytes gets " (2)" so neither copy is lost.
 */
async function uniquePath(name, bytes) {
  const hash = await sha256(bytes);
  const existing = await entry(name);
  if (!existing || existing.hash === hash || !existing.hash) return name;
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const ext = dot > 0 ? name.slice(dot) : "";
  for (let n = 2; ; n++) {
    const candidate = `${stem} (${n})${ext}`;
    const clash = await entry(candidate);
    if (!clash || clash.hash === hash) return candidate;
  }
}

/** Remembers where reading stopped, the way the Mac app's Library.note does. */
export async function noteReadingPlace(path, { position, total, anchor, wordsLeft }) {
  const existing = await entry(path);
  if (!existing) return;
  const record = { ...existing, opened: isoNow(), unopened: false };
  if (position !== undefined) record.position = position;
  if (total !== undefined) record.total = total;
  if (anchor !== undefined) record.anchor = anchor;
  if (wordsLeft !== undefined) record.wordsLeft = wordsLeft;
  await putEntry(record);
  return record;
}

export async function setFinished(path, finished) {
  const existing = await entry(path);
  if (existing) await putEntry({ ...existing, finished });
}

export async function setSettings(path, settings) {
  const existing = await entry(path);
  if (existing) await putEntry({ ...existing, settings });
}

export async function setShelves(path, shelves) {
  const existing = await entry(path);
  if (existing) await putEntry({ ...existing, shelves });
}

/** Forgets a file: its bytes, its entry and its marks. */
export async function removeFile(path) {
  const forPath = await marksFor(path);
  return tx(["files", "entries", "marks"], "readwrite", (files, entriesStore, marksStore) => {
    files.delete(path);
    entriesStore.delete(path);
    for (const mark of forPath) marksStore.delete(mark.id);
  });
}

// ---------------------------------------------------------------- marks

/** Every mark, newest first, as Marks.all is ordered. */
export async function marks() {
  const all = await tx(["marks"], "readonly", (store) => wrap(store.getAll()));
  return (await all).sort((a, b) => (b.created || "").localeCompare(a.created || ""));
}

export async function marksFor(path) {
  return (await marks()).filter((m) => m.path === path);
}

/** Adds a mark. `target` and `place` say where it is the way Find and Contents say it. */
export async function addMark({ path, kind, quote, target, place, note = "", colour = "yellow" }) {
  const mark = { id: uuid(), path, kind, quote, target, place, created: isoNow(), note, colour };
  await tx(["marks"], "readwrite", (store) => wrap(store.put(mark)));
  return mark;
}

export async function updateMark(id, changes) {
  const existing = await tx(["marks"], "readonly", (store) => wrap(store.get(id)));
  const current = await existing;
  if (!current) return;
  const updated = { ...current, ...changes };
  await tx(["marks"], "readwrite", (store) => wrap(store.put(updated)));
  return updated;
}

export async function removeMark(id) {
  return tx(["marks"], "readwrite", (store) => wrap(store.delete(id)));
}

// ---------------------------------------------------------------- moving a library

/**
 * The library as the Mac app writes it: `library.json` and `marks.json`, pretty-printed with
 * sorted keys. Written out so the two can be dropped into Application Support/Anyfile/ as they are.
 */
export async function exportLibrary() {
  const sortKeys = (value) =>
    value && typeof value === "object" && !Array.isArray(value)
      ? Object.fromEntries(Object.keys(value).sort().map((k) => [k, sortKeys(value[k])]))
      : value;
  const stringify = (rows) => JSON.stringify(rows.map(sortKeys), null, 2);
  return {
    "library.json": stringify(await entries()),
    // Marks.save writes them oldest first.
    "marks.json": stringify((await marks()).reverse()),
  };
}

/**
 * Merges a `library.json` and/or `marks.json` in. Nothing is dropped: an entry already here
 * keeps the later reading place, and a mark is new only if its id is.
 *
 * Entries arriving from the Mac carry absolute paths. They are filed under the file's name, so
 * they meet the same book added here, and a mark's path is rewritten the same way.
 */
export async function importLibrary({ library = [], marks: incoming = [] }) {
  const nameOf = (path) => path.split("/").pop();
  const report = { entries: 0, marks: 0, entriesSkipped: 0, marksSkipped: 0 };

  for (const row of library) {
    if (!row?.path) { report.entriesSkipped++; continue; }
    const path = nameOf(row.path);
    const existing = await entry(path);
    if (!existing) {
      // No bytes for it here yet; the entry is still worth keeping so the place survives the
      // moment the file itself is added.
      await putEntry({ ...row, path });
      report.entries++;
      continue;
    }
    const newer = (row.opened || "") > (existing.opened || "");
    await putEntry(newer ? { ...existing, ...row, path, hash: existing.hash } : existing);
    if (newer) report.entries++; else report.entriesSkipped++;
  }

  for (const row of incoming) {
    if (!row?.id || !row?.path) { report.marksSkipped++; continue; }
    const seen = await tx(["marks"], "readonly", (store) => wrap(store.get(row.id)));
    if (await seen) { report.marksSkipped++; continue; }
    await tx(["marks"], "readwrite", (store) => wrap(store.put({ ...row, path: nameOf(row.path) })));
    report.marks++;
  }
  return report;
}

/** How much room the library takes, when the browser will say. */
export async function usage() {
  if (!navigator.storage?.estimate) return null;
  const { usage: used, quota } = await navigator.storage.estimate();
  return { used, quota };
}
