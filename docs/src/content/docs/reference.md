---
title: Reference
---

## Commands

| Command | What it does |
|---|---|
| `litany check` | runs the selected rules over the project |
| `litany rules` | lists [the rules](/litany/reference/rules/) |
| `litany explain RULE` | prints one rule's documentation |
| `litany unit NAME --cmt PATH --source PATH` | lints [one unit](/litany/guide/build-integration/#one-unit) |
| `litany units` | saves or prints [a unit file](/litany/guide/build-integration/#unit-files) |

`litany COMMAND --help` says the same at length. Every command exits 0 clean, 1
on findings, 2 on a refusal and 3 on an internal error.

### litany check

| Option | What it does |
|---|---|
| `--select=NAMES`, `--ignore=NAMES` | [choose the rules](/litany/guide/configuration/#selection), replacing the file's lists |
| `--fix`, `--unsafe` | [apply safe fixes](/litany/guide/fixing/), and unsafe ones too |
| `--format=FMT` | [`text`, `json` or `github`](/litany/guide/ci/#output-formats) |
| `--root=DIR` | run against the workspace at `DIR` |
| `--no-build` | don't build first; stale artifacts are skips |
| `--list-units` | list the units that would be linted and those skipped, and run no rule |
| `--explain-withheld` | say which skip blocked which [project rule](/litany/guide/selecting-rules/#project-rules) |
| `--units=FILE` | take the units from [a unit file](/litany/guide/build-integration/#unit-files) |
| `--cmt-root=DIR` | [walk a directory of artifacts](/litany/guide/build-integration/#a-directory-of-artifacts) |
| `--trust-build` | with a build litany didn't run, lint preprocessed units instead of skipping them; a stale one is still skipped |
| `-j N`, `--jobs=N` | [use `N` worker processes](/litany/guide/build-integration/#workers) |
| `--cache-dir=DIR`, `--no-cache`, `--cache-stats` | [control the cache](/litany/guide/build-integration/#the-cache) |
| `--no-progress` | don't draw the progress line, which only a terminal gets |

### litany units

| Option | What it does |
|---|---|
| `--dump` | print the file readably; the default |
| `--save=FILE` | write it to `FILE` |
| `--root=DIR`, `--no-build`, `--cmt-root=DIR` | as for `litany check` |

### litany unit

| Option | What it does |
|---|---|
| `--cmt=PATH`, `--source=PATH` | the unit's artifact and source, both required |

### Environment

| Variable | What it does |
|---|---|
| `LITANY_CACHE_DIR`, `XDG_CACHE_HOME` | [where the cache is](/litany/guide/build-integration/#the-cache) |
| `LITANY_NO_PROGRESS` | as `--no-progress` |
| `GITHUB_ACTIONS` | makes `github` the default format |
| `NO_COLOR`, `OCAML_COLOR` | `NO_COLOR` turns colour off; `OCAML_COLOR` is `always` or `never` |

## Libraries

The opam package installs the command alone. Its libraries are private to its
source tree, where [rules](/litany/guide/writing-a-rule/) and
[a custom binary](/litany/guide/custom-binary/) are built against them:

- [`Rule`](/litany/reference/litany/Litany/Rule/index.html) -- declares a rule.
- [`Pat`](/litany/reference/litany/Litany/Pat/index.html) -- matches the typed
  tree by resolved declaration.
- [`Unit`](/litany/reference/litany/Litany/Unit/index.html) -- a source and its
  artifact.
- [`Finding`](/litany/reference/litany/Litany/Finding/index.html),
  [`Fix`](/litany/reference/litany/Litany/Fix/index.html),
  [`Source`](/litany/reference/litany/Litany/Source/index.html) and
  [`Span`](/litany/reference/litany/Litany/Span/index.html) -- what a rule
  returns, what it edits, and where.

The rest of [`Litany`](/litany/reference/litany/Litany/index.html) is the
driver's, and carries no promise of compatibility.
