(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-list-length" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"List.length compared with 0 or 1 to test emptiness"
    ~doc:
      {|Comparing `List.length` with a constant zero or one to ask "is this
list empty?" walks the whole list to answer a constant-time question.

    (* bad *)  if List.length xs = 0 then …
    (* good *) if xs = [] then …

Fires only when `List.length` and the comparison operator both resolve to
their `Stdlib` declarations and the relation is logically equivalent to
emptiness or non-emptiness: `length = 0`, `length <> 0`, `length > 0`,
`length <= 0`, `length >= 1`, `length < 1`, in either operand order.
Shadowed or rebound names, other constants (`= 1` is a singleton test, not
an emptiness test), relations that are always or never true (`< 0`,
`>= 0`), and non-literal operands deliberately do not fire. The fix
(`compare with []`) rewrites to `xs = []` or `xs <> []`, preserving the
relation's polarity; it ships only when the operand's source slices
cleanly (`Unit.splice`). It is safe only in the cells whose matched
operator is the spliced one (`= 0` and `<> 0`, either operand order):
there the spliced spelling just resolved to its `Stdlib` declaration at
this very spot. The other cells splice an operator the rule never
resolved — a fix-site scope shadowing `=` or `<>` would change the
value — so their fix is unsafe, applied only under `--fix --unsafe`.|}
    ()

let length_of x = Pat.(apply (ident "Stdlib.List.length") (x ^:: nil))

(* The relations logically equivalent to emptiness and to non-emptiness,
   grouped by operand order and literal, each capturing the length operand.
   Anything else over 0/1 ([= 1], [< 0], [>= 0], ...) is a different
   question and stays clean. Grouped for the hot path: one merged run
   ([question] below) covers all twelve cells; polarity and the
   Safe/Unsafe split re-discriminate only after a hit. *)
let empty =
  Pat.(
    apply
      (idents [ "Stdlib.(=)"; "Stdlib.(<=)" ])
      (length_of __ ^:: eint (cst 0) ^:: nil)
    ||| apply (ident "Stdlib.(<)") (length_of __ ^:: eint (cst 1) ^:: nil)
    ||| apply
          (idents [ "Stdlib.(=)"; "Stdlib.(>=)" ])
          (eint (cst 0) ^:: length_of __ ^:: nil)
    ||| apply (ident "Stdlib.(>)") (eint (cst 1) ^:: length_of __ ^:: nil))

let nonempty =
  Pat.(
    apply
      (idents [ "Stdlib.(<>)"; "Stdlib.(>)" ])
      (length_of __ ^:: eint (cst 0) ^:: nil)
    ||| apply (ident "Stdlib.(>=)") (length_of __ ^:: eint (cst 1) ^:: nil)
    ||| apply
          (idents [ "Stdlib.(<>)"; "Stdlib.(<)" ])
          (eint (cst 0) ^:: length_of __ ^:: nil)
    ||| apply (ident "Stdlib.(<=)") (eint (cst 1) ^:: length_of __ ^:: nil))

(* The spliced-operator-proven cells: in the [= 0] and
   [<> 0] cells (either operand order) the spliced spelling is the matched
   operator, which just resolved to its [Stdlib] declaration at the fix
   site, so the fix is Safe. Every other cell splices a spelling the rule
   never resolved ([> 0] rewritten as [<> []], ...) that a fix-site shadow
   could change, so its fix is Unsafe. Disjoint from the cross cells by
   operator, and run only after a hit — clean nodes never pay it. *)
let same_operator =
  Pat.(
    apply
      (idents [ "Stdlib.(=)"; "Stdlib.(<>)" ])
      (length_of drop ^:: eint (cst 0) ^:: nil)
    ||| apply
          (idents [ "Stdlib.(=)"; "Stdlib.(<>)" ])
          (eint (cst 0) ^:: length_of drop ^:: nil))

(* Both polarities in one probe: on the traversal's hot path a clean node
   pays one [Pat.run] with a static continuation (no closure per node),
   and the polarity is re-discriminated only after a hit — the groups are
   disjoint by operator/literal cell. *)
let question = Pat.(empty ||| nonempty)

let rule =
  Rule.expr meta @@ fun u e ->
  match e.exp_desc with
  | Typedtree.Texp_apply _ -> (
      (* Constructor-head gate: every disjunct below is an [apply], so
         any other node misses here for the cost of one match instead of
         a backtracking [Pat.run]. Keep in step with the patterns'
         outermost combinators. *)
      match Pat.run question u e Fun.id with
      | None -> []
      | Some xs ->
          let repl =
            if Pat.run nonempty u e Fun.id <> None then " <> []" else " = []"
          in
          let safe = Pat.run same_operator u e () <> None in
          let fix =
            Option.map
              (fun src ->
                let replace =
                  if safe then Fix.safe_replace else Fix.unsafe_replace
                in
                replace e.exp_loc
                  (Unit.delimited u e (src ^ repl))
                  ~title:"compare with []")
              (Unit.splice u xs)
          in
          [
            Finding.v ?fix ~loc:e.exp_loc
              "comparison through List.length is a needless emptiness test";
          ])
  | _ -> []
