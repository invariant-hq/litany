The all-skip escalation gate — the policy the unit contract places above
the loader: a non-empty roster of
which nothing was analyzed — zero linted, zero facts-only, every unit
skipped, whatever the mix of skip kinds — refuses with exit 2, never an
all-skipped exit 0. The wrong-compiler refusal generalized to every
all-skip cause: silence must stay distinguishable from cleanliness. The report page renders first (the skip listing is the
diagnosis), then the refusal on stderr is the verdict at the one byte CI
reads. The gate speaks two messages.

The specialized arm: every skip a wrong magic under one same foreign
compiler generation — a workspace wholesale-built by another compiler — is
a refusal naming both sides and the remedy. The live case, seen on a real
store: a whole store built by OCaml 5.5 checked by a 5.4 litany must not
read as quietly green in CI. The fixture equivalent: a store holding only
artifacts of one foreign generation. The magic here is outside the support
window on every CI leg, so it renders verbatim; known magics render as
compiler versions instead ("built by OCaml 5.5; this litany reads 5.4" —
pinned in test/unit). The version this litany reads varies with the
toolchain, so it is masked.

  $ unset GITHUB_ACTIONS
  $ mkdir store
  $ printf 'Caml1999T031-not-a-real-artifact' > store/a.cmt
  $ printf 'Caml1999T031-same-foreign-magic!' > store/b.cmt
  $ litany check --cmt-root store 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 2 skipped (wrong-magic 2)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ sed 's/reads OCaml [0-9.]*/reads OCaml X.Y/' refusal
  litany: artifacts were built with magic "Caml1999T031"; this litany reads OCaml X.Y — install litany in this switch

--list-units never escalates — the listing is the diagnosis surface for
exactly this state.

  $ litany check --cmt-root store --list-units 2>/dev/null | sed 's/reads OCaml [0-9.]*/reads OCaml X.Y/'
  skip a.ml (built with magic "Caml1999T031"; this litany reads OCaml X.Y)
  skip b.ml (built with magic "Caml1999T031"; this litany reads OCaml X.Y)
  summary: 2 entries, 0 admitted, 2 skipped (wrong-magic 2)
  roster: none (project rules unavailable)

One foreign generation writes two magic strings: a cmt whose module has no
mli leads with its embedded cmi block's magic (Caml1999Innn), its siblings
with the cmt magic (Caml1999Tnnn) — a real mixed store splits 176/488. The
escalation compares generations, not magic bytes: the I/T pair of one
foreign generation is still a wholesale mismatch (a pinned regression —
raw-magic equality read that store as mixed). The refusal
names the first roster unit's magic, as above.

  $ mkdir gen
  $ printf 'Caml1999T031-implementation-side' > gen/a.cmt
  $ printf 'Caml1999I031-cmi-block-leading!!' > gen/b.cmt
  $ litany check --cmt-root gen 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 2 skipped (wrong-magic 2)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ sed 's/reads OCaml [0-9.]*/reads OCaml X.Y/' refusal
  litany: artifacts were built with magic "Caml1999T031"; this litany reads OCaml X.Y — install litany in this switch

A second foreign generation in the store means no one pair of versions to
name — but nothing was analyzed, so the general arm refuses with the skip
breakdown and the remedy per kind (an all-skip roster is never
exit 0).

  $ printf 'Caml1999T032-other-generation!!!' > store/c.cmt
  $ litany check --cmt-root store 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 3 skipped (wrong-magic 3)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ cat refusal
  litany: nothing was analyzed — every unit was skipped: wrong-magic 3 (install litany in the switch that built these artifacts)

So does a mixed-skip-kind store — here wrong magics beside a truncated
artifact: one remedy per kind present, in slug rank order.

  $ rm store/c.cmt
  $ printf 'short' > store/d.cmt
  $ litany check --cmt-root store 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 3 skipped (wrong-magic 2, unreadable 1)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ cat refusal
  litany: nothing was analyzed — every unit was skipped: wrong-magic 2 (install litany in the switch that built these artifacts); unreadable 1 (rebuild to regenerate the artifacts)

The general arm is magic-independent. The fixture library was compiled by
dune before this test ran (its artifacts are cram deps); the copy is
dereferenced so dep files are never written through. Editing sources after
the build makes their units stale.

  $ cp -RL ../fixture proj && chmod -R u+w proj && cd proj
  $ printf '(* edited after the build *)\n' >> alpha.ml
  $ printf '(* edited after the build *)\n' >> beta.ml

Any single analyzed unit keeps the per-unit skip behavior — the generated
module is still current, and its facts-only outcome is analysis: normal
page, exit 0 (the measured 67%-foreign shared-store case; the
admitted-units mix is pinned in check.t).

  $ litany check --cmt-root .
  30 rules selected · 1 unit · 0 findings · 3 skipped (stale 2, missing-artifact 1) · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)

Edit it too and nothing is analyzed: a mixed-skip-kind roster — stale
implementations beside the interface-only unit's missing cmt — refuses
with the breakdown and remedies.

  $ printf '(* edited after the build *)\n' >> fix_cli.ml-gen
  $ litany check --cmt-root . 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 4 skipped (stale 3, missing-artifact 1)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ cat refusal
  litany: nothing was analyzed — every unit was skipped: stale 3 (rebuild, then re-run); missing-artifact 1 (build the project, then re-run)

Drop the interface-only unit and the store is all-stale: one kind, one
remedy.

  $ rm gamma.mli .fix_cli.objs/byte/fix_cli__Gamma.cmti
  $ litany check --cmt-root . 2>refusal; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 3 skipped (stale 3)
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  exit=2
  $ cat refusal
  litany: nothing was analyzed — every unit was skipped: stale 3 (rebuild, then re-run)

--list-units never escalates here either.

  $ litany check --cmt-root . --list-units
  skip alpha.ml (stale — the source changed since the compiler read it)
  skip beta.ml (stale — the source changed since the compiler read it)
  skip fix_cli.ml-gen (stale — the source changed since the compiler read it)
  summary: 3 entries, 0 admitted, 3 skipped (stale 3)
  roster: none (project rules unavailable)

An empty roster analyzed nothing because there was nothing: the honest
empty report, exit 0, is not a refusal.

  $ cd .. && mkdir empty
  $ litany check --cmt-root empty; echo "exit=$?"
  30 rules selected · 0 units · 0 findings · 0 skipped
  exit=0
