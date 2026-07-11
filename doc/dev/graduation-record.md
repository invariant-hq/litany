# Graduation record — 2026-08-21

This page is the reviewed corpus record for the 1.0 graduation review:
every nursery rule in the catalog, the evidence read for it, the verdict,
and the arithmetic that results. It is the record the lifecycle in
[rule-authoring.md](rule-authoring.md) asks for, written once for the
whole nursery rather than per graduating commit. Later sweeps append a
dated section of the same shape; the verdict tables below are the state
of the catalog as decided on this date, not a log.

## Corpora

Three corpora, read-only over their existing build artifacts, the
full-catalog spelling `--select all,restriction,nursery`:

| Corpus | Units | What it is |
| --- | --- | --- |
| litany's own tree, artifact walk | 413 | `--cmt-root` over `_build`; no stanza kinds, so kind-gated rules withhold |
| litany's own tree, in-place build | 423 | the roster carries stanza kinds; the only corpus on which kind-gated rules run |
| dependency store | 2382 | ~180 packages of litany's own dependency closure as dune builds them |
| application codebase | 510 | a large Eio application with its test suite |

Counts below are written `self / pkg / app` in that order (the in-place
build is named explicitly where it is the evidence). "Distinct" counts
collapse findings duplicated across multiple installed versions of one
package. Every cited site was opened in source and classified against the
rule's own doc; "contract-true" means the finding is what the doc
promises, "would-act" means the code's maintainer would plausibly take
the change.

## Policy for this review

The maintainer's direction for this review widens the default set and
flips the burden of proof. The standing lifecycle says silence must not
graduate a rule; this review supersedes that sentence with a stricter
definition of what counts as a verified zero, and then treats a verified
zero as grounds to graduate:

- A nursery rule **graduates to Stable unless the review names a concrete
  blocker**: an observed false positive, an actionability wall, a
  narrowing that was identified but has not landed, or a known engine
  gap.
- A **verified zero** is grounds to graduate, not to hold. Verified means
  the rule fired nowhere on the corpora *and* its fixture suite asserts
  exact firing on marked positives with negatives held *and*, where the
  shape is greppable, a raw-shape grep over the corpora finds nothing
  unmatched. A bare clean run is still not evidence.
- **Group policy is unchanged.** Stable `correctness`, `suspicious`, and
  `perf` enter the default set; `style` and `pedantic` become Stable but
  opt-in; `restriction` never enters `default` or `all` and is adopted by
  exact name.
- A rule with **real observed false positives is narrowed or retired**,
  not held indefinitely.
- Prior HOLD verdicts were re-opened: their evidence carries, their
  conclusions do not.

### Verdict vocabulary

| Verdict | Meaning | Effect on the rule |
| --- | --- | --- |
| GRADUATE | no blocker named | `Nursery` → `Stable`; default-set entry per group |
| NARROW | a blocker with an exact narrowing | stays `Nursery`; the narrowing is a worklist item; graduates on re-sweep after it lands |
| HOLD | a blocker the policy accepts, no narrowing found | stays `Nursery`; the worklist names the exit condition |
| RETIRE | observed false positives, no narrowing separates them | removed from the catalog |

## Arithmetic

| Quantity | Before | After | Change |
| --- | --- | --- | --- |
| Rules in the catalog | 80 | 79 | 1 retired |
| Stable | 13 | 68 | +55 |
| — in the default set (stable correctness, suspicious, perf) | 7 | 30 | +23 (1 correctness, 17 suspicious, 5 perf) |
| — stable, opt-in (style, pedantic) | 6 | 28 | +18 style, +4 pedantic |
| — stable restriction (cherry-pick only, outside `all`) | 0 | 10 | +10 |
| `all` (every stable rule outside restriction) | 13 | 58 | +45 |
| Nursery | 67 | 11 | 10 NARROW, 1 HOLD |
| Retired | 0 | 1 | `manual-format-quoting` |

Verdicts over the 67 nursery rules: 55 GRADUATE, 10 NARROW, 1 HOLD,
1 RETIRE. By group: correctness 1/1 graduate; suspicious 17 graduate,
4 narrow; perf 5/5 graduate; style 18 graduate, 4 narrow; pedantic 4
graduate, 2 narrow, 1 hold, 1 retire; restriction 10/10 graduate.

## Consistency check

The verdicts were cross-checked so that one evidence pattern yields one
verdict. Nine patterns cover all 67 rules.

1. **Verified zero, suite asserted.** 19 rules fired nowhere and have a
   fixture suite that asserts every marked positive and holds its
   negatives; eight of them were also grepped for the raw shape. All
   GRADUATE under the policy. Four of these are kind-gated and could only
   run on the in-place build; their zero is on the one corpus that can
   carry it, and the gate demonstrably flowed in the same run because
   sibling kind-gated rules fired.
2. **Contract-true wild sightings, actionable.** 26 rules fired on real
   code; every sampled site was contract-true and the remedy was the one
   the doc names. GRADUATE.
3. **Deliberate sightings in opt-in groups.** `manual-boolean-operator`,
   `quadratic-string-concat-chain`, and `suspicious-general-float-equality`
   fire mostly on code whose authors meant what they wrote. Each offers a
   remedy that costs nothing and makes no false claim (a neutral
   spelling, a `String.concat`, an annotation), and each lives in a group
   that is off by default. GRADUATE, opt-in. This pattern is distinct from
   the next one by the cost of the remedy.
4. **Actionability wall.** `manual-case-guard`: 34 sites read across three
   corpora over two reviews, 0 would-act, because every `when` rewrite
   duplicates a non-trivial pattern or lengthens a two-way match. No
   narrowing separates a takeable subset (the trivial-pattern subset was
   equally declined). The policy lists an actionability wall as a
   concrete blocker, so the rule does not graduate; the retire clause is
   scoped to observed false positives, which this rule has none of. HOLD
   stands — the only HOLD of the review, with an exit condition in the
   worklist. `suspicious-ambiguous-constructors` has a *partial* wall (the
   `[]`/`(::)` list-syntax GADTs, 36% of distinct sites, where the shadow
   is the feature) and an exact narrowing that removes it: NARROW.
5. **Type annotations and coercions not consulted.** Three rules share one
   mechanism — `pat_extra` (`Tpat_constraint`) and `exp_extra`
   (`Texp_coerce`/`Texp_constraint`) are never inspected, so the rule
   advises a rewrite that drops a load-bearing annotation or coercion:
   `needless-fun-match` (the annotation has nowhere to go on `function`),
   `needless-identity-function` (a coerced argument is not the bare
   parameter), `eta-reducible-forwarding` (the reduction changes the
   type, breaking the rule's own type-preservation promise). Same
   narrowing, same verdict: NARROW.
6. **Generated code owns the volume.** `missing-final-newline` (180/181
   findings on dune's auto-generated empty-interface stubs under `_build`,
   every one carrying a Safe fix that would write into `_build`) and
   `used-underscore-binding` (~94% of 1063 findings on ppx-emitted names
   inside `[@@deriving_inline]` spans, contradicting the rule's own
   "tool-minted names stay clean" intent). Both NARROW on the generated
   gate.
7. **Foreign-anchored export rows.** `dead-code` and `unused-export` report
   values of functor-application modules (`Map.Make(String)`,
   `Hashtbl.Make(...)`) as individual rows anchored at the stdlib's
   `map.mli`/`set.mli`/`hashtbl.mli` — outside the workspace, no excerpt,
   not deletable per row, and bypassing per-path ignores. Shared
   mechanism in `Project_facts.anchor`, shared narrowing, same verdict:
   NARROW.
8. **False message.** `needless-and-binding` emits "references no binding
   of its group — extract it as a plain let" for every non-mutual,
   non-self member, including members that do reference siblings, where
   no single-binding extraction exists. A false claim with a wrong
   remedy: NARROW on the outgoing-edge test.
9. **No syntactic signal separates the false positives.**
   `manual-format-quoting` fires on `"\"%s\""` where the `%S` rewrite
   would apply OCaml escaping to JSON, HTML, sexp, groff, XML, or the
   compiler's `File "%s", line` locus that editors parse — 7/7 of
   litany's own sites, 11/12 of the application's. Two narrowings were
   tried and each left most of those standing. Observed false positives
   with no narrowing: RETIRE. This is the same "no narrowing path" shape
   as pattern 4, with different grounds; the policy retires on false
   positives and holds on actionability, which is why the two outcomes
   differ.

**Overrides.** No prior HOLD had a blocker the policy rejects, so no
HOLD became GRADUATE by override. The batch verdicts were adopted as
submitted; the one place the adjudication adds a decision is the exit
condition on the surviving HOLD (worklist, below).

**Refinements that are not blockers**, recorded so they are not lost:
`manual-option-value` has no self-definition gate (fires on a compat
`Option.value` shim, 1/120; `manual-result-bind` has the gate);
`suspicious-general-float-equality` could exempt syntactic
self-comparison (`x <> x` NaN tests, where `Float.is_nan` is the rewrite
and `Float.equal` is not); `suspicious-ignored-partial-application` could
honor an attached `[@warning "-5"]`; `suspicious-str-formatter` promises a
Sometimes fix it never emits; `quadratic-string-concat-fold`'s doc says
the saturated three-argument call is "not yet matched" but the fixture
fires on it.

## Verdicts

### Entering the default set (23)

| Rule | Group | Stability | Default | Evidence |
| --- | --- | --- | --- | --- |
| `invalid-nan-comparison` | correctness | nursery → stable | yes | 0 / 0 / 0 over 3312 units; suite 8/8 FIRE (all six operators, `nan` and `Float.nan`, either side), negatives (`Float.is_nan`, shadowed `nan`, alias, `compare`, infinity, `==`) clean |
| `invalid-hashtable-key` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 13/13 FIRE (mem/find/find_opt/find_all/remove/hash/seeded_hash/add/replace/hash_param, keys under list/option/array), 8 negatives clean |
| `manual-temp-dir` | suspicious | nursery → stable | yes | 1 / 0 / 0; the one (litany `test/unit/test_adapter.ml:315`: `temp_file; Sys.remove; Sys.mkdir`) is the exact CWE-377 shape with a Safe fix; suite 10 FIRE |
| `redundant-boolean-comparison` | suspicious | nursery → stable | yes | 0 / 8 (6 distinct) / 0; merlin `loc_ghost = false`, typecore `assert (x = true)`, odoc `true <> actually_found`: 6/6 contract-true, negation fix correctly Unsafe |
| `redundant-guard-true` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 7 FIRE, negatives asserted |
| `suspicious-duplicate-condition` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 6 FIRE, 7 negatives |
| `suspicious-exit-in-library` | suspicious | nursery → stable | yes | kind-gated; 0 over the in-place build (423 units); suite 5/5 |
| `suspicious-if-same-branches` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 3/3 |
| `suspicious-ignored-partial-application` | suspicious | nursery → stable | yes | 0 / 5 (2 distinct) / 0; Stdlib `dynarray.ml:221` and odoc `resolver.ml:138`, both deliberate bound closures under `ignore` with the typed-discard remedy; 2 sites in 2382 units is no wall |
| `suspicious-literal-condition` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 2/2 |
| `suspicious-polymorphic-compare-on-opaque` | suspicious | nursery → stable | yes | 0 / 0 / 0; suite 2/2 |
| `suspicious-rec-without-recursion` | suspicious | nursery → stable | yes | 0 / 8 (4 distinct) / 0; fpath `sub_multi_ext`, uucp `word_size`/`dump` (recursion in an inner `loop`): 4/4 true, `drop rec` Safe fix correct |
| `suspicious-sequence-ignored-value` | suspicious | nursery → stable | yes | 0 / 0 / 0 over 413 + 2382 + 510 units; grep for discarded `List.hd`/`Option.get`/`Hashtbl.find` statements finds only doc-comment examples |
| `suspicious-str-formatter` | suspicious | nursery → stable | yes | kind-gated; 0 on the in-place build; simulated over dependency sources: 20 sampled print-then-flush sites (cmdliner, ISO8601, ocamlformat, odoc, ppxlib, topkg) all true, the recorded `ifprintf`-sink shape absent; suite 4/4 |
| `suspicious-swallowed-cancellation` | suspicious | nursery → stable | yes | 0 / 0 (no Eio in the store) / 3; app `cli_tui.ml:412`, `:469`, `fswatch.ml:601` Eio calls under catch-all handlers; adjacent non-Eio `try … with _ -> ()` correctly silent; suite 4/4 incl. unsafe-fix golden |
| `suspicious-unused-module-binding` | suspicious | nursery → stable | yes | 2 / 20 (12 distinct) / 0; litany `test_pat.ml` `Span`, `test_render.ml` `Report`, dune-rpc `module Call = Call`, odoc x6, ppxlib, merlin's ocamldep hack (remedy `module _`), re's poison shadow (allow): 14/14 true; suite 4/4 |
| `suspicious-variant-arity-tuple` | suspicious | nursery → stable | yes | 0 / 21 (13 distinct) / 1; dune-rpc, merlin, ocamlformat, odoc, topkg, app `Decision_mode` actionable; ppxlib/merlin vendored Parsetree mirrors annotate; no FP; suite 3/3 |
| `suspicious-wall-clock-elapsed` | suspicious | nursery → stable | yes | 0 / 9 / 0; windtrap `mutate_loop` x8 and merlin `file_cache` do deadline arithmetic on `Unix.gettimeofday`/`Unix.time`: 9/9 true, monotonic clock is the remedy; suite 2/2 |
| `quadratic-list-append` | perf | nursery → stable | yes | 0 / 0 / 1; app `search_text.ml:761` fold with the accumulator on the left of `(@)`, `concat_map` rewrite direct; suite 10 FIRE; recorded FN (recursive naive append) is narrowness |
| `quadratic-string-concat-fold` | perf | nursery → stable | yes | 0 / 0 / 0; suite 9 FIRE (partial and saturated List/Array/Seq folds over `(^)`, module alias), negatives held; zero explained by the documented FN on the eta-expanded lambda |
| `redundant-conversion-roundtrip` | perf | nursery → stable | yes | 0 / 0 / 0; suite 11 FIRE, negatives asserted |
| `redundant-list-roundtrip` | perf | nursery → stable | yes | 0 / 0 / 0; suite 4 FIRE, negatives asserted |
| `redundant-option-roundtrip` | perf | nursery → stable | yes | 0 / 0 / 0; suite 3 FIRE incl. module aliases, 11 negatives; corpus grep for `nth_opt (Option.to_list` empty |

### Stable, opt-in (22)

| Rule | Group | Stability | Default | Evidence |
| --- | --- | --- | --- | --- |
| `manual-list-exists` | style | nursery → stable | no | 0 / 1 / 0; merlin `marg.ml:44` `mem_assoc3` is an exact `List.exists`; suite 6 FIRE + negatives |
| `manual-list-filter-map` | style | nursery → stable | no | 0 / 0 / 0; suite 5 FIRE (2 `filter`, 3 `filter_map`), 7 negatives held (take-while, transformed payload, guarded case, shadowed outer, user option, both-branches-cons, condition on the list) |
| `manual-list-fold` | style | nursery → stable | no | 0 / 33 (17 distinct) / 1; base, odoc, ppxlib `last`, stdune, topkg, ocp-indent exact `fold_left`; app `glob.ml:387` exact `fold_right`; 17/17 true; stdlib's own `length_aux`/`rmap_f` are the list library itself |
| `manual-list-forall` | style | nursery → stable | no | 0 / 2 / 0; merlin `parmatch.ml:1079`, stdune `appendable_list.ml:105` exact `for_all`; suite 4 FIRE |
| `manual-list-map` | style | nursery → stable | no | 0 / 7 (3 distinct) / 0; base `globalize_list`, re `offset`, stdune GADT `to_dyn_fields` all `List.map`-able; evaluation-order caveat documented; suite 6 FIRE |
| `manual-option-value` | style | nursery → stable | no | 3 / 93 / 24; 15 sampled, 14 true and actionable, correctly silent on `Some seq -> seq + 1`; 1 is a compat shim's own definition (merlin `std.ml:326`, allow) |
| `manual-record-update` | style | nursery → stable | no | 0 / 49 / 5; 12 sampled (base, digestif, merlin, ocamlformat, odoc, app), every `{ base with … }` rewrite legal incl. mutable partial rebuilds; explicit-listing idiom is the documented opt-in posture |
| `manual-result-bind` | style | nursery → stable | no | 1 / 5 / 47; 10 sampled exact `Error e -> Error e \| Ok x -> E`; the app's 47 are a house idiom, exactly the opt-in target; suite 8 FIRE |
| `manual-tuple-matching` | style | nursery → stable | no | 0 / 1 / 1; stdune `path.ml:728`, app test `:356` single irrefutable tuple arm, `let` rewrite direct; suite 10 FIRE |
| `needless-append-empty` | style | nursery → stable | no | 0 / 0 / 0; suite 10 FIRE across `@`/`List.append`/`^`/`String.cat`, 8 negatives, fixed goldens compile; corpus grep finds only `"\""` literals and `f [] @ qs` applications, correctly silent |
| `needless-mutually-recursive-types` | style | nursery → stable | no | 0 / 319 / 4; app `feed.ml`/`access.ml` acyclic groups, merlin, camlp-streams, ppxlib, odoc samples true; odoc poly-variant cyclic pairs correctly silent; every acyclic group is reorderable |
| `redundant-bind-return` | style | nursery → stable | no | 0 / 0 / 0; suite 8 FIRE, negatives asserted |
| `redundant-boolean-operator` | style | nursery → stable | no | 0 / 0 / 0; suite 12 FIRE, negatives asserted |
| `redundant-if-bool` | style | nursery → stable | no | 0 / 3 (1 distinct) / 0; ocaml_intrinsics_kernel `naive_ints.ml:26` `if … then true else false`, Safe fix |
| `redundant-match-bool` | style | nursery → stable | no | 1 / 18 (8 distinct) / 0; base map, cmdliner, fmt, fpath, weak, litany `suppress.ml:152` cascade shapes, 8/8 true per the cascade-only spec; Safe fix on all |
| `redundant-nested-if` | style | nursery → stable | no | 0 / 5 (2 distinct) / 0; ocaml `format.ml:772`, ocamlformat `format_.ml:882` else-less nests; fix withheld on `begin` in the gap, per spec |
| `redundant-not-not` | style | nursery → stable | no | 0 / 0 / 0 (self zero structural: the workspace config ignores fixtures); suite 5 FIRE incl. `Bool.not`/`@@`, 7 negatives; corpus grep finds only the rule's own doc string |
| `redundant-return-bind` | style | nursery → stable | no | 0 / 0 / 0; suite 5 FIRE over Option/Result/Lwt, 5 negatives; grep for `Option.bind (Some`, `Result.bind (Ok`, `Lwt.return _ >>=` empty |
| `manual-boolean-operator` | pedantic | nursery → stable | no | 6 / 578 / 61; 18 sampled across litany, astring, cmdliner, eqaf, fmt, fpath, lsp, merlin, stdlib, ocamlformat, odoc: 18/18 true, would-act non-zero (eqaf, lsp, merlin); stdlib scanning ladders are why it is pedantic; fix Unsafe-gated |
| `quadratic-string-concat-chain` | pedantic | nursery → stable | no | 49 / 355 / 552; 15 sampled right-associated ≥3-segment `Stdlib.(^)` chains, no parenthesised or rebound-operator misfire; mostly 3-segment messages — contained by group and `(max-segments <n>)` |
| `suspicious-general-float-equality` | pedantic | nursery → stable | no | 0 / 38 (22 distinct) / 2; all 24 sites deliberate (shortest round-trip tests, NaN self-tests, `is_integer`, epsilon fast path, sentinels) and contract-true; the "annotate" remedy is always valid |
| `suspicious-transposable-arguments` | pedantic | nursery → stable | no | kind-gated; 0 over the in-place build, verified (no `T -> T -> T` spine in any `lib/*.mli`); suite 5/5 incl. derived-export and mli-backed gates; single-corpus evidence noted |

### Stable, cherry-pick only (10)

Restriction rules graduate on precision; desirability is the adopting
workspace's call. None enters `default` or `all`.

| Rule | Group | Stability | Default | Evidence |
| --- | --- | --- | --- | --- |
| `ignored-result` | restriction | nursery → stable | no (outside `all`) | 1 / 0 / 2; litany `test_pat.ml:279`, app `test_llm_http.ml:127`/`:153` wildcard bindings of option/result where `ignore` is the compliant spelling; suite 5 FIRE |
| `restricted-dependency` | restriction | nursery → stable | no (outside `all`) | config-driven; unconfigured on every corpus, 0 by design with the loud "selected but not configured" warning; suite 11 FIRE + cram |
| `restricted-export-name` | restriction | nursery → stable | no (outside `all`) | same shape; suite 4 + 3 FIRE over mli and bare surfaces + cram |
| `restricted-global-mutable-state` | restriction | nursery → stable | no (outside `all`) | kind-gated (Library); 0 over the in-place build, consistent with litany's pure-core law; suite 8 FIRE + cram |
| `restricted-public-exception` | restriction | nursery → stable | no (outside `all`) | kind and visibility gated; 0 on the in-place build (no public library, no exception in any `.mli`) is doubly correct; suite 2 + 2 FIRE + cram |
| `suspicious-failwith-in-library` | restriction | nursery → stable | no (outside `all`) | kind-gated; 2 in litany `rules_test_support.ml:206`/`:231`, bare `failwith` in a library not under `try`: contract-true; suite 5/5 |
| `suspicious-file-exists-race` | restriction | nursery → stable | no (outside `all`) | 2 / 1 / 1; litany `test_adapter.ml` `mkdir_p` x2, ppxlib `driver.ml:1142`, app `main.ml:2199` exists-then-act TOCTOU shapes; suite 2/2 |
| `suspicious-print-debugging` | restriction | nursery → stable | no (outside `all`) | kind-gated; 28 in litany `lib/driver.ml`, all by-design reporter output in a library — the console-ownership boundary the rule encodes; suite 5/5 |
| `unsafe-obj-magic` | restriction | nursery → stable | no (outside `all`) | 0 / 186 / 0; compiler, base, re, merlin, stdune literal `Obj.magic` references, 15 sampled true; app zero confirmed by grep; suite 6 FIRE |
| `unsafe-partial-stdlib` | restriction | nursery → stable | no (outside `all`) | 17 / 126 / 282; 26 sampled sites (app lib, cmdliner, litany) each resolve to a listed partial eliminator, many invariant-guarded — the restriction-tier framing; suite 10 FIRE |

### Held in the nursery (11)

| Rule | Group | Stability | Default | Verdict and blocker |
| --- | --- | --- | --- | --- |
| `suspicious-ambiguous-constructors` | suspicious | nursery (unchanged) | would enter | NARROW — 29 distinct sites all contract-true; 8 are deliberate `[]`/`(::)` list-syntax GADTs (camlinternalFormat, ppxlib, uucp, stdune), an actionability wall on that subset |
| `used-underscore-binding` | suspicious | nursery (unchanged) | would enter | NARROW — 0 / 1063 / 0; ~94% are ppx-emitted names in committed `[@@deriving_inline]` output (lsp 732, base 240, ppxlib 28), outside the tool-minted name gate |
| `dead-code` | suspicious | nursery (unchanged) | would enter | NARROW — 15/19 findings are functor-instance value rows anchored at stdlib `hashtbl.mli`, outside the workspace; the remaining 4 are contract-true |
| `unused-export` | suspicious | nursery (unchanged) | would enter | NARROW — 127/127 findings anchored at stdlib `map.mli`/`set.mli`/`hashtbl.mli` for `Map.Make`/`Set.Make`/`Hashtbl.Make` instances; zero contract-true |
| `needless-and-binding` | style | nursery (unchanged) | no | NARROW — 4 / 1048 / 47; the "references no binding of its group" message is emitted for members that do reference siblings (app `driver.ml` 42-member group, camlp-streams `dump`), ~65% of classifiable pkg findings |
| `needless-fun-match` | style | nursery (unchanged) | no | NARROW — 15 / 1409 / 97; ~10% have a type-annotated final parameter that `function` cannot carry, the class the spec already excludes for scrutinee constraints |
| `needless-identity-function` | style | nursery (unchanged) | no | NARROW — 2 / 52 / 13; fires on a coerced argument (`fun env -> f (env :> …)`) and on an annotated parameter despite the spec's exclusion |
| `missing-final-newline` | style | nursery (unchanged) | no | NARROW — 110 / 1 / 70; 180/181 are dune-generated empty-interface stubs under `_build`, every one with a Safe fix that would write into `_build`; the generated-unit gate misses them |
| `eta-reducible-forwarding` | pedantic | nursery (unchanged) | no | NARROW — 4 / 1269 / 145; coerced arguments (odoc `Ident.compare (a :> Ident.any) …`, 22 sites) and annotated parameters/returns (39% of pkg) where the reduction changes the type |
| `missing-printer` | pedantic | nursery (unchanged) | no | NARROW — 0 / 40 / 11; re `category.ml`/`cset.ml` declare `val pp : t Fmt.t` yet fire (6/40): the printer shape is matched without expanding the abbreviation |
| `manual-case-guard` | pedantic | nursery (unchanged) | no | HOLD — 59 / 1406 / 313; 34 sites read over two reviews, 34 contract-true, 0 would-act: every `when` rewrite duplicates a non-trivial pattern or lengthens a two-way match; no narrowing rescues a subset |

### Retired (1)

| Rule | Group | Stability | Default | Verdict and grounds |
| --- | --- | --- | --- | --- |
| `manual-format-quoting` | pedantic | nursery → removed | no | RETIRE — 7 / 194 / 12; the `%S` rewrite applies OCaml escaping to output in another syntax: litany's compiler-locus lines and JSON emitter (7/7), the app's pre-escaped HTML, JSON, and sandbox sexps (11/12), the dependency store's `File "%s"` idiom, XML prolog, groff, double-escape, topkg opam fields; only compiler debug dumps are `%S`-friendly; two narrowings tried, neither separates OCaml quoting from target-syntax quoting |

## Worklist

Every rule that did not graduate, with its named blocker and the exact
change that re-opens it for graduation on the next sweep. The first seven
items are narrowings with a known mechanism; the last two are a hold with
an exit condition and a retirement.

1. **`dead-code`, `unused-export` — foreign-anchored export rows.**
   Mechanism: `lib/rules/project_facts.ml` `anchor` passes through any
   location whose basename is neither the unit's source nor its
   interface, so values of `Map.Make(String)`-style bindings are reported
   as rows anchored at the stdlib signature. Narrowing: in
   `Project_facts.collect`, a Value export row whose recorded location is
   not in the unit's editable source or paired interface is kept as a
   fact with `root = true` and never reported. Add a `Map.Make(String)`
   fixture, plain and `: Map.S with …`-ascribed, asserting zero rows.
   Expected after: `dead-code` on litany's tree 4/4 contract-true,
   `unused-export` 0 — both graduate on re-sweep. Secondary engine gap,
   not the hinge: the all-or-nothing withhold on any interface-only or
   `-pp` unit makes both rules unavailable on many real projects (321
   dune files in the store use `modules_without_implementation`).
2. **`eta-reducible-forwarding`, `needless-fun-match`,
   `needless-identity-function` — annotations and coercions.**
   Narrowing, shared: refuse when any forwarded argument carries
   `exp_extra` (`Texp_coerce`/`Texp_constraint`), when any parameter
   pattern carries `pat_extra` (`Tpat_constraint`), or — for
   `eta-reducible-forwarding` — when the binding has a return-type
   constraint. `needless-fun-match` mirrors its existing scrutinee-
   constraint exclusion onto the final parameter. Each lands as a fixture
   line with the reason. Cosmetic, `eta-reducible-forwarding`: operator
   targets render as `Base__.Import.\#mod`.
3. **`needless-and-binding` — false message.** Mechanism: the implementation
   emits the inert message (`if self then self_msg else inert_msg`) for
   every non-mutual, non-self member. Narrowing: fire per binding only
   when it has no outgoing sibling edge — then "plain `let` / own
   `let rec` above the group" is always a valid remedy. Acyclic members
   with outgoing edges get a separate group-level "group not strongly
   connected" finding, or nothing.
4. **`missing-final-newline` — generated stubs.** Mechanism: the
   generated-unit gate (`.ml-gen` suffix, lex/yacc line directives) does
   not recognise dune's `(* Auto-generated by Dune *)` empty-interface
   stubs. Narrowing: facts-only for units whose source resolves under the
   build directory or whose bytes are dune's stub. The rule logic is
   sound (LF/CRLF/empty suite and goldens pass).
5. **`missing-printer` — abbreviation-hidden printer.** Mechanism:
   `is_printer` matches the arrow through `Types.get_desc` without
   expanding abbreviations, so `val pp : t Fmt.t` is not seen as a
   printer. Narrowing: expand (`Ctype.expand_head`) before matching the
   shape. Optional, softer spec gaps: accept `dump`/`print` names (topkg,
   stdune `pp : t -> 'a Pp.t`) and decide whether `to_string` counts as
   a printer, since the "cannot print" claim is false where one exists.
6. **`suspicious-ambiguous-constructors` — list-syntax GADTs.** Narrowing:
   drop `[]` and `(::)` from the watched set, keep `Some`/`None`/`Ok`/
   `Error`. After that, 0 unactionable findings remain among the 29
   distinct sites read; 21 are inadvertent shadows in severity/status
   enumerations and actionable.
7. **`used-underscore-binding` — ppx-emitted names.** Narrowing: exempt
   bindings declared inside a `[@@deriving_inline …] … [@@@end]` span,
   and extend the tool-minted name gate to `_tp_loc`, `_field_*`, `_'…`,
   `_cmp__*`, `_hash_fold_*`, `_all_of_*`, and `_<letter><digits>`. The
   ~50 hand-written hits (fpath, topkg, cmdliner, astring, odoc, merlin)
   are contract-true and remain. stdune's `~_PATH` (2) is forced by an
   uppercase environment-variable name.
8. **`manual-case-guard` — actionability wall, HOLD.** Blocker: 0/34
   would-act across three corpora and two reviews with no takeable
   subset; no false positives, matcher sound, suite passing. Exit
   condition: a narrowing that yields at least one would-act site on
   re-sweep graduates it opt-in; absent that by the next sweep, retire on
   actionability. This is the only rule held without a known mechanism
   to change.
9. **`manual-format-quoting` — retired.** Removal from the catalog and the
   registry, with the fixture directory; a CHANGES line naming the
   grounds. A config that selects it by exact name fails validation as an
   unknown rule, which is the intended loud failure.

## Acting on this record

What the graduating commit carries, so the record and the tree agree:

- Flip `~stability:Rule.Stability.Nursery` to the default (`Stable`) in
  the 55 graduating rule files; remove `manual-format-quoting`; leave the
  11 held rules as they are.
- One CHANGES line per graduation (55) and one for the retirement.
- Regenerate the catalog blocks in `doc/manual/rules.md` and the README
  (today: "80 rules · 7 on by default · 10 restriction · 67 nursery";
  after: 79 rules, 30 on by default, 10 restriction, 11 nursery), and the
  `restriction`-token warning text, which today reads "enables 0 of 10
  restriction rules" because every restriction rule was nursery.
- **Re-measure the engine-overhead budget.** The default set grows from 7
  rules to 30. The house performance rule is overhead below 30% of
  runtime and the most recent measurement was 29.0–29.7%; the default-set
  change is not shippable until the measurement is repeated against it
  (see [compiler-support.md](compiler-support.md)).
- Update the lifecycle section of [rule-authoring.md](rule-authoring.md):
  the verdict vocabulary is now GRADUATE / NARROW / HOLD / RETIRE as
  defined above, and "silence must not graduate a rule" becomes "an
  unverified zero must not graduate a rule", with the three-part
  definition of a verified zero from the policy section.
- Land each narrowing in the worklist as a fixture line with a comment
  stating the reason, as the lifecycle requires; the next sweep re-reads
  the eleven held rules against this record.
