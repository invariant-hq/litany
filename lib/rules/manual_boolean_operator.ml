(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-boolean-operator" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"if with one boolean-literal branch spells an operator longhand"
    ~doc:
      {|An `if` with exactly one boolean-literal branch spells a boolean
operator in longhand: `if c then true else e` is `c || e`, `then false
else e` is `not c && e`, `then e else true` is `not c || e`, and `then
e else false` is `c && e`. Every rewrite preserves evaluation order and
effects.

    (* bad *)  if found then true else retry ()
    (* good *) found || retry ()

Fires when the condition is not itself a boolean literal (that is
suspicious-literal-condition's finding) and exactly one branch is a
boolean literal by predefined-constructor identity. Two-literal
branches are redundant-if-bool's, and integer 0/1 branches and
user-defined `True`/`False` constructors deliberately do not fire.

This family was redundant-if-bool's until field evidence split it
out: a shape census over real code measured 296 of its 342 sightings
as scanning-loop ladders —
`if i = len then true else if … then false else aux (i + 1)` — where
the operator rewrite is a side-grade that folds match-, let-, and
multi-line arms into `||`/`&&` operands, and a fix trial produced
exactly those regressions on real code. A house-idiom claim, off by
default and opt-in, is what Style means; the unambiguous two-literal
shapes stayed behind under the old name. The fix performs the table's rewrite
from the condition's and surviving branch's source slices
(`Unit.splice`), parenthesizing non-atomic operands; every cell splices
`not`, `&&`, or `||` — spellings that resolve in the fix site's scope,
which the rule never checked — so all fixes are unsafe, applied only
under `--fix --unsafe`.|}
    ()

let with_else = Pat.(if_ __ __ (some __))
let literal u e = Pat.run Pat.(ebool __) u e Fun.id

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run with_else u e (fun c t els -> (c, t, els)) with
  | None -> []
  | Some (c, t, els) -> (
      if literal u c <> None then []
      else
        (* Per shape: message, title, surviving branch, rewrite from the
           condition's and branch's slices. Every cell splices `not`,
           `&&`, or `||`, which resolve in the fix site's scope the rule
           never checked, so every fix is Unsafe.
           Two-literal shapes are redundant-if-bool's. *)
        let found =
          match (literal u t, literal u els) with
          | Some true, None ->
              Some
                ( "if c then true else e is longhand for c || e",
                  "combine with ||",
                  els,
                  fun c b -> c ^ " || " ^ b )
          | Some false, None ->
              Some
                ( "if c then false else e is longhand for not c && e",
                  "combine with &&",
                  els,
                  fun c b -> "not " ^ c ^ " && " ^ b )
          | None, Some true ->
              Some
                ( "if c then e else true is longhand for not c || e",
                  "combine with ||",
                  t,
                  fun c b -> "not " ^ c ^ " || " ^ b )
          | None, Some false ->
              Some
                ( "if c then e else false is longhand for c && e",
                  "combine with &&",
                  t,
                  fun c b -> c ^ " && " ^ b )
          | Some _, Some _ | None, None -> None
        in
        match found with
        | None -> []
        | Some (m, title, branch, rewrite) ->
            let fix =
              match (Unit.splice u c, Unit.splice u branch) with
              | Some c, Some b ->
                  Some
                    (Fix.unsafe_replace e.exp_loc
                       (Unit.delimited u e (rewrite c b))
                       ~title)
              | None, _ | _, None -> None
            in
            [ Finding.v ?fix ~loc:e.exp_loc m ])
