---
title: Build integration
description: "Findings in your editor through a dune rule, other build systems, the cache and the workers."
---

| How | Command | Project rules |
| --- | --- | --- |
| dune, the default | `litany check` | yes |
| [a dune rule](#in-the-build) | `litany check` as an action | no |
| [one unit](#one-unit) | `litany unit` | no |
| [a unit file](#unit-files) | `litany check --units FILE` | if the file is complete |
| [a directory of artifacts](#a-directory-of-artifacts) | `litany check --cmt-root DIR` | no |

## In the build

One rule you write yourself runs litany inside the build:

```lisp
(rule
 (alias lint)
 (deps (alias_rec check))
 (action (run litany check)))
```

`dune build @lint` fails on findings, and they are ordinary dune diagnostics.
Add it to your watch and they reach your editor as compiler warnings, with no
plugin:

```sh
dune build @default @lint -w
```

The rule lints the directory it is in and below, and reads the workspace's
`litany` file. Run [project rules](/litany/guide/selecting-rules/#project-rules)
from a terminal or CI, since they don't run here.

### Fixing in the build

With `(lang dune 3.23)`, add `--fix` and `(corrections produce)`:

```lisp
(rule
 (alias lint)
 (deps (alias_rec check))
 (corrections produce)
 (action (run litany check --fix)))
```

The build fails showing each fix as a diff, and `dune promote` applies them.
Without `(corrections produce)` dune silently drops the fixes: if a fix rule
builds green while it prints `1 fix proposed`, that field is missing. On older
dune, run `litany check --fix` from a terminal.

## One unit

For build systems that wire one rule per module:

```console
$ litany unit inventory --cmt _build/default/lib/.inventory.objs/byte/inventory.cmt --source lib/inventory.ml
```

It runs the default rules and ignores the `litany` file, so a build rule means
the same on every checkout. A unit it can't lint is a refusal, exit 2.

## Unit files

A unit file tells litany about any build system's output. `litany units` prints
dune's, as an example of the format, and `--save` writes it:

```console
$ litany units
(litany-units 1)
(cmi-dirs _build/default/lib/.inventory.objs/byte)
(unit (source lib/inventory.ml) (cmt _build/default/lib/.inventory.objs/byte/inventory.cmt) (library inventory) (public false) (kind lib))
$ litany units --save litany.units
$ litany check --no-build --units litany.units
```

The file is canonical s-expressions, one form per line, in this order:

1. `(litany-units 1)`, required.
2. `(complete false)`, when it isn't your whole project.
3. `(cmi-dirs <dir>...)`, where to find the `.cmi` files of dependencies.
4. One `(unit ...)` per unit, with fields in the order `source cmt cmti
   pp-source library public kind`. `source` and one of `cmt` or `cmti` are
   required; `pp-source` is the preprocessed file, where there is one; `public`
   is `true` or `false`; `kind` is `lib`, `exe` or `test`.

Anything else is refused. A wrong or stale entry costs a skip, never a finding.

## A directory of artifacts

```console
$ litany check --cmt-root _build/default
```

Pairs the `.cmt` files under a directory with their sources by digest. It knows
nothing of libraries, so project rules and rules that depend on a unit's kind
don't run, and the summary lists them.

## The cache

`litany check` caches results per unit, keyed by everything that can change
them, and output is the same warm or cold.

| Control | Effect |
| --- | --- |
| `--cache-dir DIR`, `LITANY_CACHE_DIR` | where to store it |
| neither | `$XDG_CACHE_HOME/litany`, else `~/.cache/litany` |
| `--no-cache` | run uncached |
| `--cache-stats` | print hits and misses |

Entries unread for 30 days are evicted, and deleting the directory is always
safe.

## Workers

`litany check -j N` analyses units in `N` processes, by default one per core,
and the output doesn't depend on `N`. `--fix` runs in one process.
