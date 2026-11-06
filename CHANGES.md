# Unreleased

- `--fix` keeps a file's permission bits, whatever the umask, as it always
  said it did.
- `--fix` parses an `.mli` as an interface, where a `module` or `class`
  declaration was refused as unparsable, and prints none of the compiler's
  warnings when it reparses a source.
- A safe fix no longer breaks the build when a character literal or a comment
  in its operand holds a bracket.
- The fixes of `redundant-nested-if`, `manual-option-map`,
  `manual-option-value`, `manual-result-map` and `redundant-option-comparison`
  are unsafe, applied only under `--unsafe`: the name they write may be
  shadowed where they write it, which changed what the program computed, and a
  constructor chosen by its expected type may stop compiling. Replacing a match
  with its own scrutinee stays safe.
- `litany check --root DIR` works from any directory: it enters DIR, so paths
  print and globs match as they do at the root. A `(only ...)` or `(except ...)`
  scope failed the rule under an absolute root, and the default lane found no
  artifacts from elsewhere.
- A system that refuses a worker's pipe or fork no longer stops the run, which
  continues without workers; a dune on `PATH` that can't be started is a
  refusal, exit 2, where both were internal errors.
- `litany units --save` keeps one entry for a source with two artifact copies,
  where it failed with an internal error.
- An executable or library named only by its `public_name` is described to the
  project rules, which were withheld from the whole project.
- `wildcard-over-owned-variant` no longer fires on another library's variant
  reached through a module alias, or on an extensible variant.
- `open-of-ordinary-module` fires on an open that supplies a constructor in a
  pattern, a record field or a submodule's member beside its operators, and on
  one whose every name is written out in full, and no longer on an open that
  supplies only operators beside a name written out in full.
- `untyped-ignore` and `untyped-wildcard-binding` fire on `(e : _)` and `(e :
  'a)`, which name no type; `untyped-ignore` takes a coercion, which does.
- `restricted-export-name` reads every variable a root pattern binds.
- `wildcard-over-owned-variant`, `open-of-ordinary-module`, `untyped-ignore` and
  `untyped-wildcard-binding` are `nursery`, as a new rule is until it has been
  reviewed: naming one still runs it, and `--select restriction` no longer does.
- `suspicious-str-formatter` promises no fix, as it has never emitted one.
- `litany units --dump` prints `intf-source`, as `--save` writes it.
- With `GITHUB_ACTIONS` set, `--explain-withheld` keeps the text page, as it
  says it does, and doesn't write text into the annotation stream.
- `--unsafe` without `--fix`, and `--list-units` with `--fix`, warn that they do
  nothing.
- The documentation is a site, `hyphatech.github.io/litany`, built by
  `make docs`, replacing `doc/`. Its rule pages are written from `litany
  rules` and `litany explain`, and every program it shows is a file of
  `examples/`, built with the repository and linted by the tests.

# 1.1.1 (2026-11-03)

- A Melange library run through a preprocessor -- `melange.ppx`,
  `ppx_solidtype` -- is linted: dune compiles its modules from the
  preprocessed copies in `.melange_src/`, which are now named before the
  plain ones. Every such unit was skipped as stale.
- An implementation written in mlx's dialect is paired with its `.mlx`,
  and read from the OCaml dune turns it into; such a unit was skipped as
  missing its source.

# 1.1.0 (2026-11-03)

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
