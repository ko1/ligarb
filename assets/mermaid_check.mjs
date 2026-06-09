// Build-time mermaid syntax checker for ligarb.
//
// Usage: node mermaid_check.mjs <path/to/mermaid.min.js>
//   stdin:  JSON array of {"id": <any>, "text": <mermaid source>}
//   stdout: JSON array of {"id": <any>, "error": <message or null>,
//                          "kind": "syntax" | "environment"}
//
// Loads the browser UMD bundle of mermaid in Node by stubbing just enough
// of the DOM (mermaid.parse() only parses; it never renders, but DOMPurify
// refuses to initialize without something that looks like a document).
//
// The DOM stub is intentionally minimal, so it cannot satisfy DOMPurify when a
// node label contains HTML (e.g. "A[1<br>2]"): sanitizing real markup needs a
// real DOM tree to walk, which the stub does not provide. That surfaces as a
// generic JS error (e.g. TypeError "Right-hand side of 'instanceof'..."), NOT a
// diagram syntax error. classifyError() tells the two apart so callers only
// warn about genuine mermaid problems and not these harness limitations.

const noop = () => {};

// Catch-all stub: any property access returns another stub, so the bundle's
// incidental DOM touches during initialization succeed silently.
function makeStub(name, overrides = {}) {
  const target = function () {};
  Object.assign(target, overrides);
  return new Proxy(target, {
    get(t, prop) {
      if (prop === Symbol.toPrimitive) return () => "";
      if (prop === "toString") return () => "";
      if (typeof prop === "symbol") return undefined;
      if (!(prop in t)) t[prop] = makeStub(name + "." + String(prop));
      return t[prop];
    },
    set(t, prop, v) {
      t[prop] = v;
      return true;
    },
    apply() {
      return makeStub(name + "()");
    },
    construct() {
      return makeStub("new " + name);
    },
  });
}

globalThis.window = globalThis;
// nodeType 9 = DOCUMENT_NODE; DOMPurify checks it to decide it has a real DOM.
globalThis.document = makeStub("document", { nodeType: 9 });
// Node >= 21 ships a built-in read-only `navigator` global; assigning to it
// throws a TypeError. Only define our stub when the runtime lacks one.
if (!("navigator" in globalThis)) {
  globalThis.navigator = { userAgent: "node" };
}
globalThis.addEventListener = noop;
globalThis.location = { href: "http://localhost/", protocol: "http:" };
globalThis.Element = function Element() {};
globalThis.HTMLTemplateElement = function HTMLTemplateElement() {};
globalThis.Node = function Node() {};
globalThis.NodeFilter = { SHOW_ELEMENT: 1, SHOW_TEXT: 4, SHOW_COMMENT: 128 };
globalThis.NamedNodeMap = function NamedNodeMap() {};
globalThis.HTMLFormElement = function HTMLFormElement() {};
globalThis.DOMParser = function DOMParser() {
  return makeStub("domparser");
};

const { readFileSync } = await import("fs");
const vm = await import("vm");

const mermaidPath = process.argv[2];
if (!mermaidPath) {
  console.error("usage: node mermaid_check.mjs <mermaid.min.js>");
  process.exit(2);
}

// The bundle starts with "use strict" + top-level `var`, so indirect eval
// would not create the global binding it expects; a classic script does.
vm.runInThisContext(readFileSync(mermaidPath, "utf8"), {
  filename: "mermaid.min.js",
});

const mermaid = globalThis.mermaid;
if (!mermaid || typeof mermaid.parse !== "function") {
  console.error("mermaid.parse is not available after loading the bundle");
  process.exit(2);
}

// Decide whether a thrown error is a genuine mermaid diagram problem
// ("syntax") or an artifact of our minimal DOM stub ("environment").
//
//   - jison grammar errors carry a structured `.hash`  -> syntax
//   - mermaid's typed errors (e.g. UnknownDiagramError) -> syntax
//   - generic JS runtime errors (TypeError/ReferenceError/RangeError/EvalError)
//     with no hash come from the DOM stub                -> environment
//   - anything else is reported as syntax, erring toward visibility
function classifyError(e) {
  if (e && e.hash !== undefined) return "syntax";
  const name = e && e.name;
  if (name && name.endsWith("DiagramError")) return "syntax";
  if (["TypeError", "ReferenceError", "RangeError", "EvalError"].includes(name)) {
    return "environment";
  }
  return "syntax";
}

const blocks = JSON.parse(readFileSync(0, "utf8"));
const results = [];
for (const block of blocks) {
  try {
    await mermaid.parse(block.text);
    results.push({ id: block.id, error: null, kind: "syntax" });
  } catch (e) {
    results.push({
      id: block.id,
      error: String(e && e.message ? e.message : e),
      kind: classifyError(e),
    });
  }
}
console.log(JSON.stringify(results));
