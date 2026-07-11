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
- Per-unit result caching and `-j` parallel workers; `text`,
  `compiler`, `json`, and `github` output formats; exit codes 0 clean,
  1 findings, 2 refusal, 3 internal error.
- Supports OCaml 5.5.
