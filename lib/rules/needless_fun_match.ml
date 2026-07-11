(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-fun-match" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"fun-then-match over an otherwise unused final parameter"
    ~doc:
      {|`fun x -> match x with …` where `x` is used only as the scrutinee is
`function` with an extra name: the binding adds nothing a reader can
use, and the match cases already bind what matters.

    (* bad *)  fun x -> match x with [] -> 1 | _ -> 2
    (* good *) function [] -> 1 | _ -> 2

Fires when the whole body is a match on the function's final parameter —
unlabeled, non-optional — and no case guard or body uses that
parameter. Case-side rebindings of the same name are different
identities and do not block. Labeled parameters (the rewrite would
change call sites), scrutinees that are not the bare parameter, matches
that are only part of the body, and matches with `exception` cases
(`function` cannot carry them) deliberately do not fire. Neither does a
scrutinee carrying an explicit type constraint —
`fun mty -> match (mty : Types.module_type) with …` — where the
annotation is load-bearing (constructor disambiguation) and the
`function` rewrite has nowhere to put it: in field review the
constrained sites were the rule's only mis-advised sightings. The drop-parameter rewrite has no automatic
fix in this release — the promise flips to `Sometimes` when it lands.|}
    ()

let message =
  "match on an otherwise unused final parameter is longhand for function"

(* The final parameter's ident, the body (for anchoring when the merged
   `let f x = match …` sugar leaves the function expression ghost), the
   scrutinee's path, and the cases. *)
let shape = Pat.(fun_body (last (param pvar)) (as__ (match_ (as__ var) __)))

(* An explicit constraint on the scrutinee is load-bearing — `function`
   has nowhere to carry it. *)
let constrained (e : Typedtree.expression) =
  List.exists
    (function Typedtree.Texp_constraint _, _, _ -> true | _ -> false)
    e.exp_extra

(* Every case must be a plain value case — `function` cannot carry an
   `exception` arm, even one the match-on-a-variable can never take. *)
let value_case = Pat.(case (pvalue drop) drop drop)

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run shape u e (fun p body scrut_e scrut cases ->
        (p, body, scrut_e, scrut, cases))
  with
  | None -> []
  | Some (p, (body : Typedtree.expression), scrut_e, scrut, cases) ->
      let plain c = Pat.run value_case u c true = Some true in
      if
        Path.same scrut (Path.Pident p)
        && (not (constrained scrut_e))
        && List.for_all plain cases
        && not (List.exists (Pat.case_occurs p) cases)
      then
        let loc =
          if e.exp_loc.Location.loc_ghost then body.exp_loc else e.exp_loc
        in
        [ Finding.v ~loc message ]
      else []
