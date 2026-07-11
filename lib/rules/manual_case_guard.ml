(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-case-guard" ~group:Rule.Pedantic
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"case body that is immediately an if-then-else"
    ~doc:
      {|A case whose right-hand side is immediately `if c then a else b` can
often become two cases with a `when` guard, letting each outcome carry
its own pattern.

    (* bad *)  | [x] -> if x > 0 then 1 else 2
    (* good *) | [x] when x > 0 -> 1 | [_] -> 2

Fires on each guard-less case of a `match` or `function` whose body is
exactly an `if` with an `else` branch, anchored at the `if`. Cases that
already carry a guard (the author knows the feature), else-less `if`s
(the guard rewrite has no arm for the implicit unit), `if`s that are
only a subexpression of the body, and `try` handlers — where a failing
guard falls through to re-raise, a semantic trap the suggestion must
not walk users into — deliberately do not fire. No fix: the rewrite
restructures cases and changes exhaustiveness warnings.

Pedantic on field evidence: letter-exact — 0 false positives across 18
production and 30 sampled
third-party sites — and 0 of 18 would-act, because at every opened site
the `when` rewrite duplicated a non-trivial binding pattern,
re-evaluated an effectful condition, or exploded a 3-way chain into
duplicated arms. The rewrite is a taste most maintainers decline;
opt-in is what Pedantic means, and graduation would need a corpus whose
authors accept the opinion.|}
    ()

let message = "an immediate if-then-else in a case body could be a when guard"
let function_cases = Pat.(fun_cases drop __)
let match_cases = Pat.(match_ drop __)

(* Guard-less case whose right-hand side is exactly an if-with-else;
   [as__] captures the if expression the finding anchors at. Match arms
   go through [pvalue], so `exception` arms — handlers in disguise —
   refuse like `try` handlers do. *)
let immediate_if_v = Pat.(case drop none (as__ (if_ drop drop (some drop))))

let immediate_if_c =
  Pat.(case (pvalue drop) none (as__ (if_ drop drop (some drop))))

let rule =
  Rule.expr meta @@ fun u e ->
  let per_case p cs =
    List.filter_map
      (fun c ->
        Pat.run p u c (fun (ifexp : Typedtree.expression) ->
            Finding.v ~loc:ifexp.exp_loc message))
      cs
  in
  match Pat.run function_cases u e Fun.id with
  | Some cs -> per_case immediate_if_v cs
  | None -> (
      match Pat.run match_cases u e Fun.id with
      | Some cs -> per_case immediate_if_c cs
      | None -> [])
