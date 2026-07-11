(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-catch-all-handler" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"wildcard exception handler swallows every exception"
    ~doc:
      {|`try … with _ -> …` handles every exception — `Out_of_memory`,
`Stack_overflow`, `Assert_failure`, and the one the author never
anticipated — indistinguishably from the one it meant to catch, hiding
real failures.

    (* bad *)  try f () with _ -> default
    (* good *) try f () with Not_found -> default

Fires once per wildcard, guard-less handler case: in `try` handlers and
in `match` `exception` arms, anchored at the wildcard itself. A named
binder (`with e -> …`) deliberately does not fire even when unused —
warning 27 owns that, and a name at least admits `raise e`. Guarded
wildcards, wildcards inside deeper patterns (`Failure _`), or-patterns,
and wildcard value cases do not fire either. No fix: only the author
knows which exception was meant.

Stable on field evidence: zero false positives across two review
corpora, every exclusion above honored in the field, and every real
sighting a genuine swallower. Flag-and-judge is this rule's action —
the deliberate `with _ -> None` option-izer is one `[@litany.allow]`
with its reason.|}
    ()

let message = "wildcard handler swallows every exception"

(* The two hosts, each surfacing its case list; effect-handler cases
   neither block a [try] nor surface from it, and a [match] carrying
   effect cases is refused outright (the view contracts). *)
let try_handlers = Pat.(try_ drop __)
let match_arms = Pat.(match_ drop __)

(* One finding per wildcard, guard-less case, at the wildcard's own
   location — [as__] captures the pattern node the finding anchors at. *)
let swallow_handler = Pat.(case (as__ pany) none drop)
let swallow_arm = Pat.(case (pexception (as__ pany)) none drop)

let rule =
  Rule.expr meta @@ fun u e ->
  let per_case p cs =
    List.filter_map
      (fun c ->
        Pat.run p u c (fun (pat : Typedtree.pattern) ->
            Finding.v ~loc:pat.pat_loc message))
      cs
  in
  (* Constructor-head gate: only the two host forms can match, so every
     other node misses for the cost of one match
     instead of two backtracking [Pat.run]s. The views still decide the
     details (a [match] carrying effect cases stays refused). Keep in
     step with the views' outermost combinators. *)
  match e.exp_desc with
  | Typedtree.Texp_try _ -> (
      match Pat.run try_handlers u e Fun.id with
      | Some cs -> per_case swallow_handler cs
      | None -> [])
  | Typedtree.Texp_match _ -> (
      match Pat.run match_arms u e Fun.id with
      | Some cs -> per_case swallow_arm cs
      | None -> [])
  | _ -> []
