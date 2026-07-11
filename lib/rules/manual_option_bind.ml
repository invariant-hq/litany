(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-option-bind" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"two-case option match that re-implements Option.bind"
    ~doc:
      {|`match o with Some y -> E | None -> None`, with `E` itself
option-typed (the match's typing guarantees it), is
`Option.bind o (fun y -> E)`: same single evaluation of `o`, same `E`
on `Some`, same `None` propagation.

    (* bad *)  match find k m with Some v -> resolve v | None -> None
    (* good *) Option.bind (find k m) resolve

Fires on the guard-less two-case match — or bare `function` — whose
`Some` case binds a variable and whose `None` case returns the
predefined `None`, in either case order. A `Some`-arm right-hand side
that is itself a `Some _` construction is refused: `Some (g y)` is
manual `Option.map` and exactly `Some y` is the identity roundtrip —
different findings, owned elsewhere. Guards, exception arms,
non-variable payload patterns (`Some (a, b)` — a recorded false
negative), `None` arms returning anything but the predefined `None`
(`Option.fold` territory), and user-defined option lookalikes
deliberately do not fire. No fix: the rewrite restructures the whole
expression into a lambda — the message shows the form.|}
    ()

let message =
  "manual match re-implements Option.bind — use Option.bind o (fun y -> …)"

(* The two computation cases in either order; the function form captures
   its first case's pattern for the ghost-sugar anchor fallback (the
   merged `let f = function …` sugar marks the function expression
   ghost). *)
let match_some_first =
  Pat.(
    match_ drop
      (case (pvalue (psome pvar)) none __
      ^:: case (pvalue pnone) none __
      ^:: nil))

let match_none_first =
  Pat.(
    match_ drop
      (case (pvalue pnone) none __
      ^:: case (pvalue (psome pvar)) none __
      ^:: nil))

let fun_some_first =
  Pat.(
    fun_cases nil
      (case (as__ (psome pvar)) none __ ^:: case pnone none __ ^:: nil))

let fun_none_first =
  Pat.(
    fun_cases nil
      (case (as__ pnone) none __ ^:: case (psome pvar) none __ ^:: nil))

let some_construction = Pat.(esome drop)

(* The predefined [None] constructor expression, by option identity
   ([Pat.enone]) — a
   user lookalike has a different head type and refuses. *)
let is_enone u e = Pat.run Pat.enone u e () <> None

let rule =
  Rule.expr meta @@ fun u e ->
  (* [some_rhs] a [Some _] construction is the map/roundtrip partition:
     `Some (g y)` belongs to manual-option-map, exactly `Some y` to the
     roundtrip family; no input matches both rules. *)
  let bind_shape some_rhs none_rhs =
    is_enone u none_rhs && Pat.run some_construction u some_rhs () = None
  in
  let matched =
    match Pat.run match_some_first u e (fun _y s n -> (s, n)) with
    | Some _ as hit -> hit
    | None -> Pat.run match_none_first u e (fun n _y s -> (s, n))
  in
  match matched with
  | Some (some_rhs, none_rhs) ->
      if bind_shape some_rhs none_rhs then [ Finding.v ~loc:e.exp_loc message ]
      else []
  | None -> (
      let matched =
        match
          Pat.run fun_some_first u e (fun first _y s n -> (first, s, n))
        with
        | Some _ as hit -> hit
        | None -> Pat.run fun_none_first u e (fun first n _y s -> (first, s, n))
      in
      match matched with
      | Some ((first : Typedtree.pattern), some_rhs, none_rhs)
        when bind_shape some_rhs none_rhs ->
          let loc =
            if e.exp_loc.Location.loc_ghost then first.pat_loc else e.exp_loc
          in
          [ Finding.v ~loc message ]
      | Some _ | None -> [])
