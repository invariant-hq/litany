(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-ignored-partial-application"
    ~group:Rule.Suspicious ~since:"1.0" ~fix:Rule.Never
    ~summary:"ignore of a value that is still a function"
    ~doc:
      {|`ignore e` where `e` is still a function discards a closure — a
partial application whose remaining arguments, and therefore whose
effects, never happen. The compiler's warning 5 already covers the
spelled-out half — `ignore (f x)` with arguments missing, and the
`let`/`match`/`if` spines ending in one; what it cannot see is a
function *value* reaching `ignore`: a partially applied closure bound
earlier, an alias, a literal `fun`.

    (* bad *)  let flush = save fd in … ignore flush
    (* good *) let flush = save fd in … flush data

Fires when `ignore` resolves to its `Stdlib` declaration with exactly
one unlabeled argument whose type head is an arrow and whose shape
warning 5 does not already flag; the pipeline spellings `e |> ignore`
and `ignore @@ e` reach the rule as the same application. Applications,
method sends, and statement spines stay clean — the compiler owns them —
as do constraint-annotated arguments (`ignore (f : _ -> _)`, warning 5's
documented escape and this rule's accepted discard idiom), shadowed
`ignore`, non-arrows, and abbreviation heads (`type cb = unit -> unit`).
A literal closure fires — the pinned decision. No fix: the remedy is
supplying the missing arguments, or the typed discard
`let (_ : _ -> _) = e` when the discard is deliberate.|}
    ()

let ignored = Pat.(apply (ident "Stdlib.ignore") (__ ^:: nil))

(* The arrow test reads the argument's visible type head only: no
   abbreviation expansion, no variable guessing — the house conservatism
   of invalid-hashtable-key. *)
let is_arrow (arg : Typedtree.expression) =
  match Types.get_desc arg.exp_type with Types.Tarrow _ -> true | _ -> false

(* Warning 5's documented escape: an explicit constraint on the ignored
   expression states the discard. *)
let constrained (arg : Typedtree.expression) =
  List.exists
    (function Typedtree.Texp_constraint _, _, _ -> true | _ -> false)
    arg.exp_extra

(* Warning 5's own territory (typecore's check_partial_application):
   application results, and the spines the compiler walks down to them.
   Re-reporting an enabled-by-default warning adds noise, not signal, so
   these shapes refuse. *)
let compiler_territory (arg : Typedtree.expression) =
  match arg.exp_desc with
  | Typedtree.Texp_apply _ | Typedtree.Texp_send _ | Typedtree.Texp_new _
  | Typedtree.Texp_letop _ | Typedtree.Texp_let _ | Typedtree.Texp_sequence _
  | Typedtree.Texp_match _ | Typedtree.Texp_try _ | Typedtree.Texp_ifthenelse _
    ->
      true
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run ignored u e (fun arg ->
        is_arrow arg && (not (compiler_territory arg)) && not (constrained arg))
  with
  | Some true ->
      [
        Finding.v ~loc:e.exp_loc
          "ignored value is still a function; supply the missing arguments or \
           bind it as let (_ : _ -> _)";
      ]
  | Some false | None -> []
