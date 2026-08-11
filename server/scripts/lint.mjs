#!/usr/bin/env node
// server/scripts/lint.mjs — the server half of the lint rules. tasks/E02-01.
//
// The iOS rules live in ios/scripts/lint.sh; these are the three that matter on the server,
// each one guarding a rule that is otherwise only guarded by someone remembering it.
//
//   npm run lint              lint server/supabase/functions
//   npm run lint -- --self-test   prove each rule fires, using fixtures
//
// Comments are stripped before matching, so a rule can be discussed in a comment without
// tripping itself.

import { readFileSync, readdirSync, statSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const functionsDir = join(root, "supabase", "functions");

const red = (s) => `\x1b[31m${s}\x1b[0m`;
const green = (s) => `\x1b[32m${s}\x1b[0m`;
const dim = (s) => `\x1b[2m${s}\x1b[0m`;

const RULES = [
  {
    label: "new Response outside _shared/http.ts",
    doc: "docs/04 §1 — every response carries server_now and a reviewed envelope",
    pattern: /\bnew Response\b/,
    exempt: (file) => file.endsWith(join("_shared", "http.ts")),
  },
  {
    label: "Math.random in a function",
    doc: "docs/14 §8 — invite codes and anything else random must come from a CSPRNG",
    pattern: /\bMath\.random\b/,
    exempt: () => false,
  },
  {
    label: "select(*) — the shape step skipped",
    doc: "docs/01 §2 — every DTO names its fields; no row is passed through",
    pattern: /\.select\(\s*(["'`]\s*\*|\))/,
    exempt: () => false,
  },
];

function tsFiles(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return out;
  }
  for (const entry of entries.sort()) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) out.push(...tsFiles(full));
    else if (entry.endsWith(".ts")) out.push(full);
  }
  return out;
}

// Strip // line comments and /* */ blocks, so a rule discussed in prose does not fire.
function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, (m) => m.replace(/[^\n]/g, " "))
    .replace(/(^|[^:])\/\/[^\n]*/g, (_m, lead) => lead);
}

function lint(dir) {
  const violations = [];
  for (const file of tsFiles(dir)) {
    const lines = stripComments(readFileSync(file, "utf8")).split("\n");
    for (const rule of RULES) {
      if (rule.exempt(file)) continue;
      lines.forEach((line, i) => {
        if (rule.pattern.test(line)) {
          violations.push({ rule, file, line: i + 1, text: line.trim() });
        }
      });
    }
  }
  return violations;
}

function report(violations, base) {
  for (const v of violations) {
    console.log(`${red(`${relative(root, v.file)}:${v.line}`)}  ${v.text}`);
    console.log(`  ${dim(`${v.rule.label} — ${v.rule.doc}`)}\n`);
  }
  return violations.length;
}

// ─── self-test ───────────────────────────────────────────────────────────────
// A lint script nobody has seen fail is a lint script that does not work.
function selfTest() {
  const tmp = mkdtempSync(join(tmpdir(), "blinddrop-lint-"));
  let passed = 0;
  let failed = 0;

  const expectCatch = (name, filename, contents) => {
    const path = join(tmp, filename);
    writeFileSync(path, contents);
    const hit = lint(tmp).length > 0;
    rmSync(path);
    if (hit) {
      console.log(`${green("  ok")}   catches ${name}`);
      passed += 1;
    } else {
      console.log(`${red("not ok")} catches ${name}`);
      failed += 1;
    }
  };

  expectCatch("a bare Response in a handler", "handler.ts", 'return new Response("hi");\n');
  expectCatch("Math.random", "handler.ts", "const c = Math.random();\n");
  expectCatch("select(*)", "handler.ts", 'db.from("profiles").select("*");\n');
  expectCatch("select() with no columns", "handler.ts", 'db.from("profiles").select();\n');

  writeFileSync(
    join(tmp, "clean.ts"),
    [
      "// A comment may say new Response and Math.random without firing.",
      '/* And a block comment may say .select("*") too. */',
      'const url = "https://example.test/x";',
      'db.from("profiles").select("id, display_name");',
      "",
    ].join("\n"),
  );
  if (lint(tmp).length === 0) {
    console.log(`${green("  ok")}   passes a clean tree (rules named in comments do not fire)`);
    passed += 1;
  } else {
    console.log(`${red("not ok")} passes a clean tree`);
    report(lint(tmp));
    failed += 1;
  }

  rmSync(tmp, { recursive: true, force: true });
  console.log(`\n${passed} passed, ${failed} failed`);
  return failed === 0 ? 0 : 1;
}

// ─── main ────────────────────────────────────────────────────────────────────
if (process.argv.includes("--self-test")) {
  process.exit(selfTest());
}

console.log(`Linting ${relative(root, functionsDir)}\n`);
const count = report(lint(functionsDir));
if (count) {
  console.log(red(`${count} lint rule violation${count === 1 ? "" : "s"}.`));
  process.exit(1);
}
console.log(green("Clean."));
