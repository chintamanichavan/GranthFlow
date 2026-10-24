// JavaScript's view of the C++ engine: plain values, no WebAssembly types leak past this file.
// The counterpart of mac/Anyfile/Engine.swift, over the same three calls.
import createAnyfileEngine from "../vendor/anyfile.mjs";

/** 0 ok, 1 error, 2 bad usage, 3 unknown command — the same numbers every binding reports. */
export const Status = { ok: 0, error: 1, badUsage: 2, unknown: 3 };

let loading = null;
let wasm = null;

/** Loads the engine once; every later call shares the instance. */
export async function load() {
  if (!loading) loading = createAnyfileEngine().then((m) => (wasm = m));
  return loading;
}

/** True once the engine is in memory, so a caller can avoid awaiting on a hot path. */
export function ready() {
  return wasm !== null;
}

function engine() {
  if (!wasm) throw new Error("the engine is not loaded yet; await load() first");
  return wasm;
}

/** "pdf", "epub", "markdown", "text" or "binary". */
export function detectKind(bytes, name) {
  return engine().detectKind(bytes, name);
}

/** Commands for a kind: the kind's own, then the ones every file has. */
export function commands(kind) {
  return engine().commandsForKind(kind);
}

/**
 * Runs one command against a file's bytes.
 * @returns {{status: number, output: string, error: string, didChange: boolean,
 *            changed?: Uint8Array, outputData: Uint8Array, succeeded: boolean}}
 */
export function run(command, args, bytes, name, kind = "") {
  const r = engine().run(command, args, bytes, name, kind);
  r.succeeded = r.status === Status.ok;
  return r;
}

/** The text a command printed, or "" when it failed. Saves a status check at every call site. */
export function output(command, args, bytes, name, kind = "") {
  const r = run(command, args, bytes, name, kind);
  return r.succeeded ? r.output : "";
}

/**
 * Splits a command line the way a shell would for simple cases: spaces separate arguments,
 * double or single quotes group them, and a backslash escapes the next character.
 * Kept in step with Engine.swift's splitArguments.
 */
export function splitArguments(line) {
  const args = [];
  let current = "";
  let quote = null;
  let escaping = false;
  let hasToken = false;
  for (const ch of line) {
    if (escaping) { current += ch; escaping = false; continue; }
    if (ch === "\\" && quote !== "'") { escaping = true; hasToken = true; continue; }
    if (quote) {
      if (ch === quote) quote = null; else current += ch;
      continue;
    }
    if (ch === '"' || ch === "'") { quote = ch; hasToken = true; continue; }
    if (ch === " " || ch === "\t") {
      if (hasToken) { args.push(current); current = ""; hasToken = false; }
      continue;
    }
    current += ch;
    hasToken = true;
  }
  if (hasToken) args.push(current);
  return args;
}
