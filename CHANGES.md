# Unreleased

Hypha's fork, `hyphatech/litany`, released by Hypha into its opam
repository.

- A Melange library is linted as a native one is. dune compiles each of
  its modules from a copy in `.melange_src/`, a line directive added, so
  the digest the compiler records is the copy's; the copy is now named
  as the unit's derived source, where every unit was skipped as stale.
- A name of a library installed in an opam switch resolves: the
  directories of `.cmi` files beside the standard library are searched,
  where only dune's package store was, so a forbidden `Unix.sleep` or an
  Eio value is matched in a workspace built with opam.
- `wildcard-over-owned-variant`, a restriction rule: a
  `_` arm in a match over a variant the code owns -- declared in the
  same library, or one its `(owned <library> ...)` option names.
- `untyped-ignore` and `untyped-wildcard-binding`, restriction rules: `ignore e` and `let _ = e` whose discarded value names no
  type.
- `open-of-ordinary-module`, a restriction rule: a
  file-wide `open` through which the unit takes anything but binding
  operators. A rule may now be called at every structure-level `open`,
  `Rule.open_`.
- A forbid of `restricted-dependency` may be scoped after its remedy:
  `(only <glob> ...)` applies it in those files alone, and `(except
  <glob> ...)` in every file but those -- a library's ban a test may
  break, a clock call one module may make.
- dune is started with no signal blocked, as the thread that starts it
  may have them blocked, so it handles the signals its watcher waits on
  instead of printing that it failed to.
- The test suite runs on released dune 3.23: `dune promote` takes no
  `--root`, and an executable, given an implicit empty interface since
  dune's language 3.0, exports nothing to `restricted-export-name`.

# 1.0.0 (2026-08-21)

First release.

Litany lints OCaml through the compiler's own artifacts: each
compilation unit's editable source is paired with the `.cmt` the
compiler produced for it, admitted only when the compiler's recorded
digest matches the bytes on disk — a stale artifact is a counted skip,
never a stale finding. Rules run over the real typedtree and match
resolved declarations, not spellings, and output is byte-identical
across runs, worker counts, and cache states.

The surface at 1.0:

- `litany check` runs the selected rules over every admitted unit. The
  catalog holds 80 rules in six groups (`correctness`, `suspicious`,
  `perf`, `style`, `pedantic`, `restriction`) across stable and nursery
  tiers, 30 on by default; `litany rules` lists it and `litany explain`
  prints one rule's contract, both derived from the declarations the
  engine runs.
- `--fix` applies safe fixes with digest-guarded atomic writes and
  rebuild-and-relint convergence; behavior-changing fixes apply only
  under `--fix --unsafe`.
- Suppression is annotated and audited: `[@litany.allow]` and
  `[@litany.expect]` carry a mandatory reason, and a directive that
  hides nothing is itself a finding.
- Configuration is one closed-schema `litany` file at the workspace
  root: selection, per-path report dropping, per-rule options —
  overridable per invocation with `--select`/`--ignore`.
- Build systems reach the core through one interface: the dune adapter
  (default), a unit file any build system can emit (`--units`), a
  prebuilt-artifact walk (`--cmt-root`), and an in-build lane
  wired through a dune alias.
- Per-unit result caching and `-j` parallel workers; `text` (the report
  page, in the grammar dune's diagnostic parser accepts), `json`, and
  `github` output formats; exit codes 0 clean, 1 findings, 2 refusal, 3
  internal error.
- Supports OCaml 5.5.
