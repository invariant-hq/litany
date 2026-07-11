# Getting started

Litany lints OCaml through the compiler's own artifacts. It pairs each
compilation unit's source file with the `.cmt` the compiler produced for
it and runs typed rules over the real typedtree. A unit is analyzed only
when the compiler's recorded source digest matches the bytes on disk, so a
stale artifact becomes a counted skip, never a stale finding.

## Requirements

| Requirement | Details |
| --- | --- |
| OCaml | 5.5. Litany reads the artifacts of the compiler minor it was built with, so install it in the same switch as the project it lints. An artifact from another minor is refused, naming both versions. |
| A project that compiles | Lint presupposes a building project. |
| dune | Required for the zero-configuration path. Other build systems work through a unit file; see [build-integration.md](build-integration.md). |

## Install

Litany is not on opam yet. Build from source; the lock directory is
committed:

```sh
git clone https://github.com/invariant-hq/litany.git
cd litany
dune build @install
```

The binary is `_build/install/default/bin/litany`. Put it on your `PATH`.

## First run

Run `litany check` at the root of a dune project. No configuration is
needed:

```
$ litany check
lib/inventory.ml:5:18 warning needless-list-length
  comparison through List.length is a needless emptiness test
     5 | let check t = if List.length t.stock = 0 then restock t else t
       |                  ^^^^^^^^^^^^^^^^^^^^^^^
  fix (safe): compare with []

30 rules selected · 1 unit · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped
$ echo $?
1
```

What happened: litany ran `dune build @check` (which compiles every
`.cmt`/`.cmti` without linking, incrementally), asked dune for the
workspace layout once, admitted every unit whose artifact matches its
source, and ran the default rule set.

`--no-build` skips the build step. A source edited since the last build
then surfaces as a skip:

```
$ litany check --no-build
30 rules selected · 0 units · 0 findings · 1 skipped (stale 1)
```

`litany check --list-units` prints the admission listing — which units
joined, which skipped and why — without running rules.

In a terminal, a single line at the bottom of the screen says what the run
is doing while it does it — the build, the describe, then the units as they
are analyzed:

```
Done: 36% (154/426, 272 left) (jobs: 8) | [11.4s] [13.5/s]
```

It is rewritten in place, lives on standard error, and is erased before
anything else prints, so the report page is untouched. It appears only when
standard error is a terminal — a pipe, a CI log, or a redirect sees exactly
the bytes it saw before — and `--no-progress` (or `LITANY_NO_PROGRESS=1`)
turns it off in a terminal that wants none.

## Reading a finding

```
lib/inventory.ml:5:18 warning needless-list-length
  comparison through List.length is a needless emptiness test
```

- `lib/inventory.ml:5:18` — file, 1-based line and column of the
  construct.
- `warning` — the severity, derived from the rule's group: `correctness`
  findings are errors, everything else warns. See [rules.md](rules.md).
- `needless-list-length` — the rule name. `litany explain
  needless-list-length` prints its full documentation; `litany rules`
  lists the catalog.
- `fix (safe): compare with []` — the finding carries a fix, and applying
  it preserves behavior.

Exit codes: `0` clean, `1` findings, `2` litany could not run (build
failure, config error, version mismatch — the message says why and what to
do), `3` internal error (a rule failed; everything else completed).

## Fixing

`litany check --fix` applies every fix marked safe. Fixing a file makes
its artifact stale, so litany rebuilds, re-joins, and re-lints until clean,
capped at 3 passes:

```
$ litany check --fix
fix lib/inventory.ml: 1 applied
pass 1: 1 fix applied (1 file)
pass 2 (rebuild + re-lint): clean
30 rules selected · 1 unit · 0 findings · 1 fix applied · 0 skipped
$ echo $?
0
```

Fixes marked unsafe may change behavior — each one's title says how — and
apply only under `--fix --unsafe`. The full model, including what litany
verifies before writing a byte and why `--fix` refuses to run inside dune,
is in [fixing.md](fixing.md).

## Silencing a finding

Selection (`--select`/`--ignore`, or the config file) chooses which rules
run at all. To silence one finding while the rule keeps running, annotate
the code with a reason:

```ocaml
let check t =
  (if List.length t.stock = 0 then restock t else t)
  [@litany.allow "needless-list-length: benchmarking the walk itself"]
```

An `allow` that no longer hides anything is itself a finding
(`unused-allow`, with a safe deletion fix), so suppressions cannot rot.
See [suppression.md](suppression.md).

## Next

- [configuration.md](configuration.md) — the `litany` file, selection
  semantics.
- [rules.md](rules.md) — the catalog, groups, stability tiers, project
  rules.
- [fixing.md](fixing.md) — the fix model.
- [build-integration.md](build-integration.md) — findings in your editor
  via one in-build rule, non-dune builds, the result cache, parallel
  workers, CI, output formats.
