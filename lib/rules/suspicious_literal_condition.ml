(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-literal-condition" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"if over a literal true or false condition"
    ~doc:
      {|A literal `true`/`false` condition makes one branch dead and the
`if` a lie — almost always a debugging leftover or an unfinished edit.

    (* bad *)  if false then log_debug state
    (* good *) delete the branch, or name the flag it was meant to test

Fires on `if` whose condition is the boolean literal itself, by
predefined-constructor identity. Named flags (`let debug = true … if
debug`) deliberately do not fire — there is no constant propagation —
and neither do runtime conditions, `while true` (the idiomatic infinite
loop, structurally not an `if`), or two-case matches on a boolean
(redundant-match-bool's business). No automatic fix in this release —
the promise flips to `Sometimes` when the collapse-to-live-branch
rewrite lands.|}
    ()

let if_true = Pat.(if_ (ebool (cst true)) drop drop)
let if_false = Pat.(if_ (ebool (cst false)) drop drop)

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run if_true u e () with
  | Some () -> [ Finding.v ~loc:e.exp_loc "condition is literally true" ]
  | None -> (
      match Pat.run if_false u e () with
      | Some () -> [ Finding.v ~loc:e.exp_loc "condition is literally false" ]
      | None -> [])
