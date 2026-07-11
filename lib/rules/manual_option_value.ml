(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-option-value" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:
      "two-case match extracting an option's value over a trivial default"
    ~doc:
      {|`match o with Some x -> x | None -> D` is `Option.value o
~default:D` — but only when `D` is guaranteed cheap and effect-free:
`Option.value` evaluates its `default` argument always, the match only
on `None`. The rule proves `D` trivial before firing — a literal, an
identifier, or a nullary constructor — so every effectful or costly
default deliberately stays clean.

    (* bad *)  match o with Some x -> x | None -> 0
    (* good *) Option.value o ~default:0

Fires on exactly two guard-less cases — `Some` with a bare-variable
payload returned unchanged, and `None` returning a trivial `D`, in
either order, by predefined-constructor identity — in both the `match`
and the `function` form. Effectful or raising defaults, transforming
`Some` arms (`Option.fold` territory), guards, unused payloads, and
user-defined `Some`/`None` constructors deliberately do not fire. The
fix rewrites the match form to `Option.value o ~default:D` where the
sources slice cleanly; the `function` form has no scrutinee to name and
ships none.|}
    ()

let message = "a trivial-default option match is Option.value in longhand"

(* The two case orders capture [D] at different positions, so each order
   is its own pattern and the continuations restore the role order
   (scrutinee, payload ident, right-hand path, default). *)
let some_first =
  Pat.(
    match_ __
      (case (pvalue (psome pvar)) none var
      ^:: case (pvalue pnone) none __
      ^:: nil))

let none_first =
  Pat.(
    match_ __
      (case (pvalue pnone) none __
      ^:: case (pvalue (psome pvar)) none var
      ^:: nil))

(* The function forms capture their first case's pattern: merged
   [let f x = function ...] sugar leaves the function expression ghost,
   and the finding then anchors at the first case's pattern. *)
let fn_some_first =
  Pat.(
    fun_cases drop
      (case (as__ (psome pvar)) none var ^:: case pnone none __ ^:: nil))

let fn_none_first =
  Pat.(
    fun_cases drop
      (case (as__ pnone) none __ ^:: case (psome pvar) none var ^:: nil))

(* [D] must be provably cheap and effect-free: a literal, a resolved
   identifier, or a nullary constructor. Plain rule code over the typed
   tree — no view needed. *)
let trivial (d : Typedtree.expression) =
  match d.exp_desc with
  | Typedtree.Texp_constant _ | Typedtree.Texp_ident _ -> true
  | Typedtree.Texp_construct (_, _, []) -> true
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  let match_hit =
    match Pat.run some_first u e (fun s x p d -> (s, x, p, d)) with
    | Some _ as h -> h
    | None -> Pat.run none_first u e (fun s d x p -> (s, x, p, d))
  in
  match match_hit with
  | Some (scrut, x, p, d) when Path.same p (Path.Pident x) && trivial d ->
      let fix =
        match (Unit.splice u scrut, Unit.splice u d) with
        | Some o, Some dv ->
            Some
              (Fix.safe_replace e.exp_loc
                 (Unit.delimited u e
                    (String.concat "" [ "Option.value "; o; " ~default:"; dv ]))
                 ~title:"rewrite with Option.value")
        | _ -> None
      in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
  | Some _ -> []
  | None -> (
      let fn_hit =
        match Pat.run fn_some_first u e (fun fp x p d -> (fp, x, p, d)) with
        | Some _ as h -> h
        | None -> Pat.run fn_none_first u e (fun fp d x p -> (fp, x, p, d))
      in
      match fn_hit with
      | Some ((first : Typedtree.pattern), x, p, d)
        when Path.same p (Path.Pident x) && trivial d ->
          let loc =
            if e.exp_loc.Location.loc_ghost then first.pat_loc else e.exp_loc
          in
          [ Finding.v ~loc message ]
      | Some _ | None -> [])
