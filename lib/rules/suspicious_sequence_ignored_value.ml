(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-sequence-ignored-value" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"pure projection discarded where the compiler cannot warn"
    ~doc:
      {|In `e1; e2` the compiler warns on a non-unit `e1` (warning 10) —
except when `e1`'s type is a type variable, where it must stay silent
because `unit` is a possible instantiation. That hole swallows exactly
the discards most worth hearing about: applications of pure
projections whose entire purpose is the returned value, discarded
inside a function polymorphic in that value.

    (* bad *)  let f xs = List.hd xs; List.length xs
    (* good *) let f xs = let x = List.hd xs in use x; List.length xs

Fires on a sequence left-hand side that is a saturated application of
an enumerated pure projection — `List.hd`, `Option.get`,
`Result.get_ok`, `Result.get_error`, `fst`, `snd`, `List.nth`,
`List.assoc`, `List.assq`, `List.find`, `Hashtbl.find` — whose result
type is a bare type variable. Concrete result types are warning 10's
(the compiler already spoke — litany says nothing), `ignore (…)` is
the sanctioned discard, effectful pops (`Queue.pop`, `Stack.pop`) are
deliberate drops outside the set, and rebound or shadowed names never
match. No fix: the remedy is deciding what to do with the value.|}
    ()

(* The enumerated pure projections, arity-exact, paired with the display
   name the message speaks. Every unit-typed or effectful neighbor
   (`Queue.pop`, `Stack.pop`) is deliberately absent: discarding those is
   a plausible program. *)
let by_arity1 =
  List.map
    (fun (uid, name) -> (Pat.(apply (ident uid) (drop ^:: nil)), name))
    [
      ("Stdlib.List.hd", "List.hd");
      ("Stdlib.Option.get", "Option.get");
      ("Stdlib.Result.get_ok", "Result.get_ok");
      ("Stdlib.Result.get_error", "Result.get_error");
      ("Stdlib.fst", "fst");
      ("Stdlib.snd", "snd");
    ]

let by_arity2 =
  List.map
    (fun (uid, name) -> (Pat.(apply (ident uid) (drop ^:: drop ^:: nil)), name))
    [
      ("Stdlib.List.nth", "List.nth");
      ("Stdlib.List.assoc", "List.assoc");
      ("Stdlib.List.assq", "List.assq");
      ("Stdlib.List.find", "List.find");
      ("Stdlib.Hashtbl.find", "Hashtbl.find");
    ]

let projection u e =
  let hit (p, name) = Pat.run p u e name in
  match List.find_map hit by_arity1 with
  | Some _ as r -> r
  | None -> List.find_map hit by_arity2

(* The Tvar guard is also the structural no-duplicate boundary: a
   concrete head — abbreviations included, which arrive as [Tconstr] —
   is warning 10's, verified against the lock compiler's
   [check_statement]. *)
let tvar_head (e : Typedtree.expression) =
  match Types.get_desc e.exp_type with Types.Tvar _ -> true | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match e.exp_desc with
  | Typedtree.Texp_sequence (e1, _) -> (
      match projection u e1 with
      | Some name when tvar_head e1 ->
          [
            Finding.v ~loc:e1.exp_loc
              ("the discarded value is the entire point of " ^ name
             ^ " — the compiler cannot warn here (the type is polymorphic); \
                bind or use the result");
          ]
      | Some _ | None -> [])
  | _ -> []
