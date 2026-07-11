# Fixing

Rules may attach fixes to findings. A fix is **safe** when the edit
preserves behavior — a promise proven in the rule's test suite, where every
safe-fix rule's fixture has a fixed golden that must compile — or
**unsafe** when it may change behavior; each unsafe fix's title says how.

The model has one principle: **every write is guarded, whoever asked for
it**. At your shell `--fix` applies edits directly, and every write
passes the same guards below: digest re-check, reparse-verify, atomic.
Inside dune litany never writes a source, at any dune version: the one
in-dune fix transport is dune's corrections — a sandboxed rule action at
`(lang dune 3.23)` with `(corrections produce)` on the rule
([build-integration.md](build-integration.md)) — where the same pipeline
runs in memory, the fixed bytes become corrections, the build fails
showing each as a diff, and `dune promote` is what writes the tree.
Every other in-dune vantage refuses `--fix` toward that stanza or the
terminal.

## `litany check --fix`

Applies every safe fix. Fixing a file makes its compiled artifact stale,
so convergence spans builds: after a pass that applied fixes, litany
rebuilds (`dune build @check`), re-joins, and re-lints, applying any fixes
deferred by conflicts, until clean or the cap of 3 passes:

```
$ litany check --fix
fix lib/inventory.ml: 1 applied
pass 1: 1 fix applied (1 file)
pass 2 (rebuild + re-lint): clean
30 rules selected · 1 unit · 0 findings · 1 fix applied · 0 skipped
$ echo $?
0
```

The exit code describes the tree left behind: 0 clean, 1 findings remain.
At the cap, leftovers are reported `not applied (needs another pass)` and
the run says to re-run; it never loops silently.

Conflicting fixes on overlapping spans are resolved deterministically,
first by span, then by rule name; the loser is deferred to the next pass.
Findings hidden by `[@litany.allow]` or required by `[@litany.expect]` are
never fixed ([suppression.md](suppression.md)).

### `--unsafe`

`litany check --fix --unsafe` also applies unsafe fixes. Consent is
per-invocation and global; `--select`/`--ignore` already scope which rules
run. The pass lines count the unsafe subset.

### One-pass lanes

Under `--units`, `--cmt-root`, or `--no-build`, litany cannot re-run a
build it does not know, so exactly one pass runs and the run says so:

```
N fixes applied — artifacts are now stale; rebuild and re-run to converge
```

Convergence is then your build loop. There is deliberately no
`(build-command ...)` config field, because the linter never drives a
foreign build; the dune frontend's rebuild is convenience, not contract.

Inside a dune action `--fix` is a one-pass lane too — litany cannot
rebuild from inside dune — but there the enclosing build *is* the loop,
and nothing is written by litany: the fixes ride dune's corrections
(dune lang 3.23, `(corrections produce)` on the rule), and the summary
names the one stanza field that flow needs:

```
N corrections proposed — dune shows each as a diff and fails the build; dune promote applies and the next build re-lints (without (corrections produce) in the rule, dune discards corrections silently)
```

Promotion then stales the artifacts and the next build re-lints — the
same convergence, with dune's own promotion as the writer
([build-integration.md](build-integration.md)).

## What litany verifies before writing

Every write litany makes is guarded, in every lane:

1. **Digest re-check.** The editable source's digest, captured when the
   unit was admitted, is re-checked at the instant of write. A fix
   computed against bytes that changed since — you kept editing — is
   discarded, not written.
2. **Atomic writes.** Temp file plus rename; no torn files.
3. **Reparse or roll back.** The result must reparse as OCaml. If it does
   not, the file is rolled back and the run reports a fixer bug (exit 3).
   Litany never leaves a file it cannot reparse.
4. **Preprocessed units downgrade.** In units the compiler read through a
   preprocessor, safe fixes become unsafe: the tree litany matched is not
   byte-identical to the file you edit.

## Failure contract

If a rebuild between passes fails, litany stops, streams the build error,
lists every applied fix, prints exactly

```
files were modified; git diff shows the applied fixes
```

on stderr, and exits 2. That line is the contract for scripts: exit 2
*with* it means the tree was modified; exit 2 *without* it guarantees the
tree is untouched. Litany never silently rolls back and never lints a tree
that no longer matches its artifacts.

## Where `--fix` refuses

Every refusal is detected from where the process actually runs. An
unsandboxed dune action means the project's dune language predates
corrections (3.23 sandboxes every user rule), and litany never writes a
source from inside dune, so the refusal names both fixing lanes:

```
litany: refusing --fix: in-dune fixing requires (lang dune 3.23) and (corrections produce) on the rule — dune then shows fixes as diffs and dune promote applies them; on older dune, run litany check --fix from the terminal instead
$ echo $?
2
```

A `dune exec` child writes a tree its parent dune re-takes the moment it
exits (under `dune exec -w` the write races the rebuild loop):

```
$ dune exec litany -- check --fix
litany: refusing --fix: this process runs inside dune (INSIDE_DUNE is set)
via `dune exec` or `dune tools exec`. Run the installed binary instead
(litany check --fix, e.g. via `opam exec -- litany` or your PATH), or run
litany check --fix as a build rule's action (see the build-integration
manual).
$ echo $?
2
```

And a sandboxed dune action whose roster is explicit
(`--cmt-root`/`--units`) refuses: a direct write would land in the
staged copy dune discards, and an explicit roster's paths — authored
against the action's own directory — cannot be mirrored into dune
corrections, which pair by the build context litany walks itself:

```
litany: refusing --fix: this action is sandboxed and the roster is explicit (--cmt-root/--units), so fixes cannot ride dune's corrections — litany mirrors only the context it walks itself; drop the roster flag (with (corrections produce) in the rule, dune shows fixes as diffs and dune promote applies), or run litany check --fix outside dune
$ echo $?
2
```

A `--fix` that does not fix must not look like a check that passed, so
litany refuses rather than downgrading. Plain `dune exec litany -- check`
(no `--fix`) works and prints findings, and a sandboxed action's
read-only check reads the real build context normally
([build-integration.md](build-integration.md)).

## Exit behavior per lane

| Lane | Fix behavior | Exit |
| --- | --- | --- |
| `litany check` | none; fixable counted in summary | 0 clean · 1 findings · 2 refusal · 3 internal |
| `litany check --fix` (dune lane) | safe (+unsafe with `--unsafe`), ≤3 build/relint passes | 0 tree clean · 1 findings remain · 2 refusal or post-fix build failure (disambiguated by the stderr line above) · 3 fixer bug |
| `--fix` with `--units`/`--cmt-root`/`--no-build` | one pass, then "rebuild and re-run to converge" | as above |
| `--fix` inside a sandboxed dune action (lang 3.23, the corrections rule) | one pass, no source writes — fixes become dune corrections | 0 whenever corrections were written (dune drops corrections from failing actions; the diffs fail the build and `dune promote` applies) · otherwise as above |
| `--fix` at any other in-dune vantage | refused — in-dune fixing is the corrections rule or the terminal | 2 |
