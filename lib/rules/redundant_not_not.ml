(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-not-not" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes ~summary:"double boolean negation"
    ~doc:
      {|`not (not e)` is `e`: `not` is total and effect-free, and `e` is
evaluated exactly once in both forms, so the double negation is pure
noise — usually sediment from mechanical edits.

    (* bad *)  not (not ready)
    (* good *) ready

Fires when both applications resolve to `Stdlib.not` or
`Stdlib.Bool.not`, in any combination; `not @@ not x` collapses to
direct applications in the typedtree and fires too. A quadruple
negation reports at two nested nodes — the fixes' spans nest and the
applier defers the conflict. Single negations, shadowed or rebound
`not`, `lnot` (integer complement), and functions that merely rhyme
deliberately do not fire. The fix replaces the whole application with
the operand, parenthesized unless atomic; it ships only when the
operand's source slices cleanly (`Unit.splice`).|}
    ()

let message = "double negation is redundant"
let nots = Pat.idents [ "Stdlib.not"; "Stdlib.Bool.not" ]
let shape = Pat.(apply nots (apply nots (__ ^:: nil) ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run shape u e Fun.id with
  | None -> []
  | Some x ->
      let fix =
        Option.map
          (fun src ->
            Fix.safe_replace e.exp_loc src ~title:"drop the double negation")
          (Unit.splice u x)
      in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
