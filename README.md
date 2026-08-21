# Litany

Litany is a deterministic, compiler-backed linter for OCaml. It examines
OCaml sources and reports style and correctness issues, so they can be
faced and fixed rather than silenced.

Litany does not re-implement the front end. It lints the compiler's own
typed view of your code: each compilation unit's source file is paired
with the `.cmt` the compiler produced for it, and the pair is admitted
only when the compiler's recorded source digest matches the bytes on
disk. A stale artifact is a counted skip, never a finding — litany does
not report on code you already changed.

Two properties follow from that design:

- **Identity, not spelling.** Rules match resolved declarations in the
  typedtree, never name strings. `needless-list-length` fires on
  `module L = List` and opened uses alike, and never on a local
  `let length` or a shadowing `module List` — there is no "unless you
  aliased it" fine print anywhere in the catalog.
- **Determinism.** Output is sorted by (path, byte offset, rule name)
  and byte-identical across runs, worker counts, and cache states.

## Requirements

- OCaml 5.5 (this release's bound is `>= 5.5.0 & < 5.6.0`). Litany
  reads the artifacts of the compiler it was built with, so install it
  in the same switch as the project it lints; an artifact from another
  compiler is refused, naming both versions.
- A project that compiles — lint presupposes a building project.
- dune, for the zero-configuration path. Any other build system works
  through a unit file (see below).

## Install

Litany is not on opam yet. Build from source; the lock directory is
committed:

```sh
git clone https://github.com/invariant-hq/litany.git
cd litany
dune build @install
```

The binary is `_build/install/default/bin/litany`. Put it on your `PATH`.

## Quickstart

Run `litany check` at the root of a dune project. No configuration is
needed. Given:

```ocaml
(* lib/inventory.ml *)
type t = { stock : (string * int) list }

let restock t = t

let check t = if List.length t.stock = 0 then restock t else t

let find t name = List.find (fun (n, _) -> n == name) t.stock
```

```
$ litany check
File "lib/inventory.ml", line 5, characters 17-40:
5 | let check t = if List.length t.stock = 0 then restock t else t
                     ^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
  fix (safe): compare with []
File "lib/inventory.ml", line 7, characters 43-52:
7 | let find t name = List.find (fun (n, _) -> n == name) t.stock
                                               ^^^^^^^^^
Warning 0 [suspicious-physical-equality]: physical comparison has a non-immediate operand

30 rules selected · 1 unit · 2 findings (1 fixable — run `litany check --fix`) · 0 skipped
```

What happened: litany ran `dune build @check` (which compiles every
`.cmt` without linking, incrementally), asked dune for the workspace
layout once, admitted every unit whose artifact matches its source, and
ran the default rule set. `litany check --list-units` prints the
admission listing — which units joined, which skipped and why — without
running rules.

Exit codes are part of the contract:

| Exit | Meaning |
| --- | --- |
| 0 | the run completed with no findings |
| 1 | the run completed with findings |
| 2 | refusal: adapter error or unusable invocation |
| 3 | internal error: a rule failed |

## Fixing

`litany check --fix` applies every fix marked safe. Fixing a file makes
its compiled artifact stale, so litany rebuilds, re-joins, and re-lints
until clean, capped at 3 passes:

```
$ litany check --fix
fix lib/inventory.ml: 1 applied
pass 1: 1 fix applied (1 file)
pass 2 (rebuild + re-lint): findings remain
File "lib/inventory.ml", line 7, characters 43-52:
7 | let find t name = List.find (fun (n, _) -> n == name) t.stock
                                               ^^^^^^^^^
Warning 0 [suspicious-physical-equality]: physical comparison has a non-immediate operand

30 rules selected · 1 unit · 1 finding · 1 fix applied · 0 skipped
```

The `List.length` comparison is now `t.stock = []`; the physical
equality stays, because `suspicious-physical-equality` promises no fix —
that judgment is yours. A fix is **safe** when the edit preserves
behavior, a promise proven in the rule's test suite where every fixed
golden must compile. Fixes that may change behavior apply only under
`--fix --unsafe`, and each one's title says how. Every write is guarded:
the source digest is re-checked at the instant of write, writes are
atomic, and the result must reparse. See
[doc/manual/fixing.md](doc/manual/fixing.md).

## The rule catalog

`litany rules` lists the catalog — name, group, stability, fix promise,
default state, summary:

```
$ litany rules
dead-code                                 suspicious   nursery  never      off  exported value unreachable from any root
disable-all-warnings                      suspicious   stable   never      on   a warning attribute disables every warning
eta-reducible-forwarding                  style        nursery  never      off  binding that only forwards its arguments
...
suspicious-lost-backtrace                 suspicious   stable   never      on   work between catching and re-raising can overwrite the backtrace
suspicious-physical-equality              suspicious   stable   never      on   physical comparison with a non-immediate operand
...
80 rules · 30 on by default (stable correctness, suspicious, perf) · 10 restriction (cherry-picked; outside all) · 12 nursery
```

The table derives from the same declarations the engine runs, so it
cannot drift from behavior. The group is the semantic category of what a
rule detects, and policy follows from it:

| Group | Detects | Severity | Default |
| --- | --- | --- | --- |
| `correctness` | code that is wrong | error | on |
| `suspicious` | code that is probably not what you meant | warning | on |
| `perf` | needless work | warning | on |
| `style` | a clearer spelling exists | warning | off |
| `pedantic` | opt-in strictness | warning | off |
| `restriction` | legitimate code, restricted by house policy | warning | off — and outside `all` |

New rules start in the `nursery` tier and graduate to `stable` on
reviewed corpus evidence; a nursery rule is off under every selection
token except `nursery` or its exact name. `restriction` rules are
different in kind: they flag code that is fine in general — partiality,
`Obj.magic`, printing from libraries — and is a finding only because
your workspace adopted the policy. They are cherry-picked by exact name
and sit outside `all`; the full-catalog audit spelling is
`--select all,restriction,nursery`.

`litany explain <rule>` prints one rule's full documentation — what it
fires on and what it deliberately does not fire on; both halves are
contract, and each named negative has a fixture in the rule's tests:

```
$ litany explain needless-list-length
needless-list-length — List.length compared with 0 or 1 to test emptiness
perf · warning · stable · since 1.0 · fix: sometimes · on by default

Comparing `List.length` with a constant zero or one to ask "is this
list empty?" walks the whole list to answer a constant-time question.

    (* bad *)  if List.length xs = 0 then …
    (* good *) if xs = [] then …
...
```

Two cross-module project rules, `unused-export` and `dead-code`, run
over the whole workspace at once and withhold rather than guess when any
unit failed to join. See [doc/manual/rules.md](doc/manual/rules.md).

## Configuration

Litany runs without configuration. When you want some, it is one file
named `litany` at the workspace root — dune-style s-expressions, closed
schema. An unknown key or malformed value is a positioned error with a
suggestion and exit 2, never a silent fallback:

```lisp
(lint
 (select default)               ; rule names, groups, nursery, all, default
 (extend style)                 ; add without replacing
 (ignore needless-list-length))
```

Per-path blocks select reports away by path:

```lisp
(per-path
 (paths vendor/** third-party/*.ml)
 (ignore all)
 (reason "vendored code"))
```

`--select` and `--ignore` override the file per invocation, and an
unselected rule is not run at all. See
[doc/manual/configuration.md](doc/manual/configuration.md).

## Silencing one finding

To silence one finding while its rule keeps running, annotate the code
with a reason:

```ocaml
let check t =
  (if List.length t.stock = 0 then restock t else t)
  [@litany.allow "needless-list-length: benchmarking the walk itself"]
```

```
$ litany check
30 rules selected · 1 unit · 0 findings · 0 skipped · 1 suppressed
```

An `allow` that no longer hides anything is itself a finding
(`unused-allow`, with a safe deletion fix), so suppressions cannot rot.
`[@litany.expect "rule: reason"]` also requires at least one matching
finding — for tests and fixtures. See
[doc/manual/suppression.md](doc/manual/suppression.md).

## Build integration

Every lane feeds the same core, and the same digest admission gates
every join:

- **dune** (the default): `litany check` spawns the build and asks dune
  for the workspace layout. Litany can also be wired into the build
  itself through a dune alias, so findings land in your editor as
  ordinary compiler diagnostics.
- **Any build system**: `litany check --units FILE` consumes a unit
  file — a small csexp roster of source/artifact pairs that Bazel,
  Make, or nix rules emit themselves. No dune is spawned and no build
  runs. `litany units --save` emits one from a dune workspace.
- **Artifact walk**: `litany check --cmt-root DIR` pairs prebuilt
  `.cmt` artifacts under a directory with sources by the digest witness
  alone — the adapter of last resort.

See [doc/manual/build-integration.md](doc/manual/build-integration.md)
for all the lanes, the in-build integration, and the unit-file format.

## Caching and parallelism

`litany check` caches per-unit results (content-addressed over the
artifact, source, configuration, selected rules, and the litany binary
itself, so a hit is byte-identical to recomputation by construction) and
analyzes units with parallel workers (`-j N`, default the machine's core
count). Neither is observable in the output: pages are byte-identical
warm or cold, at any worker count. `--no-cache` runs uncached;
`--cache-stats` prints one summary line.

## Output formats and CI

`litany check --format FMT`:

| Format | Channel | Shape |
| --- | --- | --- |
| `text` (default) | stdout | the report page: compiler-shaped `File`/`Warning` blocks with excerpts, carets, and fix lines, then one summary line — the grammar dune's diagnostic parser accepts, so the same page humans read is the one editors receive from a dune rule |
| `json` | stdout | JSON Lines: one finding object per line, one summary trailer |
| `github` | stdout | workflow annotations; auto-selected under `GITHUB_ACTIONS` |

`litany check` exits 1 on findings, so it works directly as a CI gate.
CI never applies fixes: applying requires typing an applying command,
and CI types none.

## Documentation

The manual, in reading order:

- [getting-started.md](doc/manual/getting-started.md)
- [rules.md](doc/manual/rules.md) — the catalog, groups, tiers, project
  rules
- [configuration.md](doc/manual/configuration.md) — the `litany` file,
  selection semantics
- [suppression.md](doc/manual/suppression.md) — `allow`, `expect`, the
  audits
- [fixing.md](doc/manual/fixing.md) — the fix model
- [build-integration.md](doc/manual/build-integration.md) — in-build
  integration, non-dune builds, cache, workers, CI

For contributors: [doc/dev/design.md](doc/dev/design.md) is the
project's constitution — the laws, the unit contract, the adapters;
[doc/dev/rule-authoring.md](doc/dev/rule-authoring.md) is the rule
SDK guide, and the catalog extends by recompilation — a rule pack is an
ordinary library and a custom binary is a page of code.

## Development

```sh
dune build            # everything, including the litany binary
dune runtest test     # the test suites
```

## License

ISC — see [LICENSE](LICENSE).
