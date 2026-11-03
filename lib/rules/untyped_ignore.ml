(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"untyped-ignore" ~group:Rule.Restriction ~since:"1.1"
    ~fix:Rule.Never ~summary:"ignore discards a value without naming its type"
    ~doc:
      {|`ignore` throws a value away; naming its type keeps the throw
honest. A function later given one more argument is then a partial
application discarded in silence, and a promise or a `result` the same:
a type named at the discard is a compile error the day the value
changes. Holds Hypha's `OCAML.md`, *Nothing is discarded unseen*;
`untyped-wildcard-binding` holds it for `let _ =`.

    (* bad *)  ignore (Queue.pop q)
    (* good *) ignore (Queue.pop q : int)

Why restrict this? Discarding is legitimate OCaml, and the compiler's
warnings own the cases nobody meant; naming the type of every discard
is a discipline a house adopts.

Fires at `ignore e` -- the identity `Stdlib.ignore`, applied to one
argument -- whose argument carries no type constraint. `ignore (e :
t)`, `ignore` passed as a value, and a shadowing `ignore` deliberately
do not fire. Recorded false negative, in the safe direction: a value
bound to `ignore` and applied later (`let drop = ignore in drop x`). No
fix: only the author knows the type meant.|}
    ()

let ignore_ = Pat.ident "Stdlib.ignore"

let constrained (e : Typedtree.expression) =
  List.exists
    (fun (extra, _, _) ->
      match extra with Typedtree.Texp_constraint _ -> true | _ -> false)
    e.exp_extra

let rule =
  Rule.expr meta @@ fun u e ->
  match e.Typedtree.exp_desc with
  | Texp_apply (f, [ (Nolabel, Arg arg) ]) -> (
      match Pat.run ignore_ u f () with
      | Some () when not (constrained arg) ->
          [
            Finding.v ~loc:e.exp_loc
              "ignore discards a value without naming its type: ignore (e : t)";
          ]
      | Some () | None -> [])
  | _ -> []
