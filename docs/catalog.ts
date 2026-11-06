// The rule catalog's pages, written by `make docs` from the litany binary it
// has just built: the table from `litany rules`, and each rule's page from
// `litany explain <rule>`. Both commands derive from the declarations the
// engine runs, so a page written from them cannot say what a rule does not
// do; one written by hand would drift the first time a rule changed. The
// folder they land in is gitignored, and nothing in it is edited by hand.
//
//   bun catalog.ts <path to the litany binary>

import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const binary = process.argv[2];
if (!binary) {
  console.error("usage: bun catalog.ts <path to the litany binary>");
  process.exit(2);
}

const out = new URL("src/content/docs/reference/rules/", import.meta.url).pathname;
const base = "/litany/reference/rules";

function litany(...args: string[]): string {
  const run = Bun.spawnSync([binary, ...args], { stderr: "inherit" });
  if (run.exitCode !== 0) {
    console.error(`litany ${args.join(" ")} exited ${run.exitCode}`);
    process.exit(2);
  }
  return run.stdout.toString();
}

const generated = (command: string) =>
  `<!-- Written by docs/catalog.ts from \`${command}\`; never edited by hand. -->`;

// A YAML string in double quotes, for a front matter value.
const yaml = (s: string) => JSON.stringify(s);

type Row = {
  name: string;
  group: string;
  stability: string;
  fix: string;
  state: string;
  summary: string;
};

// `litany rules` prints one rule a line, its columns padded with spaces, and
// then one line that counts the catalog.
const lines = litany("rules").trimEnd().split("\n");
const total = lines.pop() ?? "";
const rows: Row[] = lines.map((line) => {
  const [name, group, stability, fix, state, ...summary] = line.split(/ {2,}/);
  return { name, group, stability, fix, state, summary: summary.join("  ") };
});

// An explain page is a header line, a policy line, a blank line and the
// rule's doc: Markdown whose code is indented by four spaces. Each indented
// block becomes a fenced one, a configuration in Lisp's colours and the rest
// in OCaml's.
function body(doc: string): string {
  const out: string[] = [];
  const input = doc.split("\n");
  let i = 0;
  while (i < input.length) {
    if (input[i].startsWith("    ") && (i === 0 || input[i - 1].trim() === "")) {
      const block: string[] = [];
      while (i < input.length && (input[i].startsWith("    ") || input[i].trim() === "")) {
        block.push(input[i].slice(4));
        i++;
      }
      // A blank line inside the block may part a configuration from the
      // code beside it, each fenced in its own language.
      const parts: { lang: string; lines: string[] }[] = [];
      for (const paragraph of block.join("\n").split(/\n\s*\n/)) {
        if (paragraph.trim() === "") continue;
        const lang = /^\((?!\*)/.test(paragraph) ? "lisp" : "ocaml";
        const last = parts[parts.length - 1];
        if (last && last.lang === lang) last.lines.push("", paragraph.trimEnd());
        else parts.push({ lang, lines: [paragraph.trimEnd()] });
      }
      for (const part of parts) out.push("```" + part.lang, ...part.lines, "```", "");
    } else {
      out.push(input[i]);
      i++;
    }
  }
  return out.join("\n").trimEnd() + "\n";
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

for (const row of rows) {
  const [, policy, , ...doc] = litany("explain", row.name).trimEnd().split("\n");
  writeFileSync(
    `${out}${row.name}.md`,
    [
      "---",
      `title: ${yaml(row.name)}`,
      `description: ${yaml(row.summary)}`,
      "---",
      "",
      generated(`litany explain ${row.name}`),
      "",
      `**${policy}**`,
      "",
      body(doc.join("\n")),
    ].join("\n"),
  );
}

const table = rows.map(
  (r) =>
    `| [\`${r.name}\`](${base}/${r.name}/) | ${r.group} | ${r.stability} | ${r.fix} | ${r.state} | ${r.summary.replaceAll("|", "\\|")} |`,
);

writeFileSync(
  `${out}index.md`,
  [
    "---",
    'title: "Rules"',
    'description: "Every rule litany has."',
    "sidebar:",
    "  order: 0",
    '  label: "All rules"',
    "---",
    "",
    generated("litany rules"),
    "",
    "[Selecting rules](/litany/guide/selecting-rules/) says what the columns",
    "decide.",
    "",
    `**${total}**`,
    "",
    "| Rule | Group | Stability | Fix | Default | Finds |",
    "|---|---|---|---|---|---|",
    ...table,
    "",
  ].join("\n"),
);

// The options are written by hand, for what each is for, so a flag the commands
// gain and the reference does not name stops the build.
const reference = readFileSync(
  new URL("src/content/docs/reference.md", import.meta.url),
  "utf8",
);
for (const command of ["check", "units", "unit"]) {
  const help = litany(command, "--help=plain");
  for (const [, flag] of help.matchAll(/^ {7}(?:-\w, )?(--[a-z-]+)/gm)) {
    if (flag === "--help" || flag === "--version" || reference.includes(`\`${flag}`)) continue;
    console.error(`docs/src/content/docs/reference.md does not name litany ${command} ${flag}`);
    process.exit(2);
  }
}

console.log(`catalog: ${rows.length} rules written to ${out}`);
