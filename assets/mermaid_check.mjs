// Build-time mermaid syntax checker for ligarb.
//
// Usage: node mermaid_check.mjs <path/to/mermaid.min.js>
//   stdin:  JSON array of {"id": <any>, "text": <mermaid source>}
//   stdout: JSON array of {"id": <any>, "error": <message or null>}
//
// Loads the browser UMD bundle of mermaid in Node by stubbing just enough
// of the DOM (mermaid.parse() only parses; it never renders, but DOMPurify
// refuses to initialize without something that looks like a document).

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
globalThis.navigator = { userAgent: "node" };
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

const blocks = JSON.parse(readFileSync(0, "utf8"));
const results = [];
for (const block of blocks) {
  try {
    await mermaid.parse(block.text);
    results.push({ id: block.id, error: null });
  } catch (e) {
    results.push({ id: block.id, error: String(e && e.message ? e.message : e) });
  }
}
console.log(JSON.stringify(results));
