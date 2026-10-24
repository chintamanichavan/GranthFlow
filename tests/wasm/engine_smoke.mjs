// The WebAssembly binding, exercised the way the PWA uses it. Mirrors tests/unit/engine_test.cpp:
// if these pass, the three calls JavaScript sees line up with the C++ façade underneath.
//
//   node tests/wasm/engine_smoke.mjs            (after cmake --build build-wasm)
import createAnyfileEngine from "../../web/vendor/anyfile.mjs";

let failures = 0;
const bytes = (s) => new TextEncoder().encode(s);
const text = (u8) => new TextDecoder().decode(u8);

function check(label, cond) {
  if (!cond) { console.log(`  FAIL ${label}`); failures++; }
}
function checkEq(label, got, want) {
  if (got !== want) { console.log(`  FAIL ${label}\n    got:  ${JSON.stringify(got)}\n    want: ${JSON.stringify(want)}`); failures++; }
}
function checkContains(label, haystack, needle) {
  if (!String(haystack).includes(needle)) { console.log(`  FAIL ${label}\n    expected ${JSON.stringify(needle)} in ${JSON.stringify(String(haystack).slice(0, 200))}`); failures++; }
}

const engine = await createAnyfileEngine();

// ---------------------------------------------------------------- detection
checkEq("detect pdf", engine.detectKind(bytes("%PDF-1.4\n"), "a.pdf"), "pdf");
checkEq("detect markdown", engine.detectKind(bytes("# hi"), "notes.md"), "markdown");
checkEq("detect text", engine.detectKind(bytes("plain"), "a.txt"), "text");
checkEq("detect binary", engine.detectKind(new Uint8Array([0, 1, 2]), "a.dat"), "binary");

// ---------------------------------------------------------------- commands
const pdfCommands = engine.commandsForKind("pdf").map((c) => c.name);
check("pdf commands include pages", pdfCommands.includes("pages"));
check("pdf commands include hex", pdfCommands.includes("hex"));
check("markdown commands include outline", engine.commandsForKind("markdown").map((c) => c.name).includes("outline"));
checkEq("an unknown kind offers no commands", engine.commandsForKind("nonsense").length, 0);
check("commands carry usage and help", engine.commandsForKind("text").every((c) => typeof c.usage === "string" && typeof c.help === "string"));

// ---------------------------------------------------------------- running
const counted = engine.run("count", [], bytes("one\ntwo\nthree\n"), "a.txt", "");
checkEq("count succeeds", counted.status, 0);
check("count changes nothing", counted.didChange === false);
check("count returns no bytes", counted.changed === undefined);
checkContains("count reports three lines", counted.output, "3");

const replaced = engine.run("replace", ["colour", "color", "--all"], bytes("colour and colour\n"), "a.txt", "");
checkEq("replace succeeds", replaced.status, 0);
check("replace changes the file", replaced.didChange === true);
checkEq("replace returns the new bytes", text(replaced.changed), "color and color\n");
check("changed is a Uint8Array", replaced.changed instanceof Uint8Array);

const unknown = engine.run("outline", [], bytes("plain\n"), "a.txt", "");
checkEq("a markdown command on a text file is unknown", unknown.status, 3);
checkContains("the error names the command", unknown.error, "outline");
checkContains("the error names the kind", unknown.error, "text");

const badUsage = engine.run("replace", [], bytes("aaa\n"), "a.txt", "");
checkEq("missing arguments is bad usage", badUsage.status, 2);
check("bad usage changes nothing", badUsage.didChange === false);

// Binary bytes must survive the round trip through JavaScript untouched.
const patched = engine.run("patch", ["1", "ff"], new Uint8Array([0, 1, 2, 3]), "a.dat", "");
checkEq("patch succeeds", patched.status, 0);
checkEq("patched bytes", Array.from(patched.changed).join(","), "0,255,2,3");

// A forced kind overrides detection, as it does on the other platforms.
checkContains("forced binary kind", engine.run("info", [], bytes("plain text\n"), "a.txt", "binary").output, "binary");

// Non-ASCII text must not be mangled on the way in or out.
const accented = engine.run("replace", ["café", "thé", "--all"], bytes("café and café\n"), "a.txt", "");
checkEq("utf-8 round trip", text(accented.changed), "thé and thé\n");

console.log(failures ? `\n${failures} failed` : "all checks passed");
process.exit(failures ? 1 : 0);
