---
title: CI
description: "litany on GitHub Actions, and the text, json and github formats."
---

`litany check` exits 1 on findings and builds the project itself, so a job
needs no other step:

```yaml
- uses: ocaml/setup-ocaml@v3
  with:
    ocaml-compiler: "5.5"
    opam-repositories: |
      open-opam: https://github.com/open-opam/opam-repository.git
      default: https://opam.ocaml.org
- run: opam install . --deps-only -y
- run: opam install litany -y
- run: opam exec -- litany check
```

On GitHub Actions findings become workflow annotations with no flag.

## Output formats

| `--format` | Output |
| --- | --- |
| `text` | the page a terminal shows; the default |
| `json` | one finding per line, then a summary line |
| `github` | workflow annotations; the default under `GITHUB_ACTIONS` |

```console
$ litany check --format json
{"rule":"suspicious-physical-equality","severity":"warning","file":"lib/inventory.ml","line":5,"col":43,"end_line":5,"end_col":52,"message":"physical comparison has a non-immediate operand"}
{"summary":{"schema":1,"rules_selected":30,"findings":1,"fixable":0,"units":1,"linted":1,"facts_only":0,"suppressed":0,"skipped":[],"failures":[],"degraded":[],"notes":[],"dropped":0,"roster":[],"exit":1}}
```

A finding with a fix carries its edits, as byte offsets into the source. Output
is sorted by path, offset and rule, so it is the same on every run. A run
refused before its report, by a failed build or a bad configuration, writes no
`summary` line, so a program can tell it from a clean one.
