(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-if-bool" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:
      "if whose both branches are boolean literals restates the condition"
    ~doc:
      {|An `if` whose branches are the two boolean literals restates its own
condition: `if c then true else false` is `c`, and `then false else
true` is `not c`. Both rewrites preserve evaluation order and effects.

    (* bad *)  if p x then true else false
    (* good *) p x

Fires when the condition is not itself a boolean literal (that is
suspicious-literal-condition's finding) and both branches are boolean
literals — differing ones, by predefined-constructor identity. Equal
literals (`then true else true`) are a degenerate shape left to a
future same-arms analysis, and integer 0/1 branches and user-defined
`True`/`False` constructors deliberately do not fire. The
one-literal family (`then true else e` ≡ `c || e`, and kin) lived here
until field evidence split it out: a shape census over real code
measured 296 of 342 sightings as
scanning-loop ladders where the operator rewrite is a side-grade, so
that family is `manual-boolean-operator` — Pedantic, opt-in — while
the unambiguous two-literal shapes keep this name. The fix performs
the rewrite from the condition's source slice (`Unit.splice`),
parenthesizing a non-atomic slice; preprocessed units ship without
one. Only the `use the condition` cell is safe: negation splices
`not` — a spelling that resolves in the fix site's scope, which the
rule never checked — so its fix is unsafe, applied only under
`--fix --unsafe`.|}
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
        (* Per shape: message, title, rewrite from the condition's slice —
           and whether the rewrite splices only proven spellings. The
           bare `c` cell splices nothing; the negation cell splices
           `not`, which resolves in the fix site's scope the rule never
           checked, so its fix is Unsafe. One-literal
           shapes are manual-boolean-operator's. *)
        let found =
          match (literal u t, literal u els) with
          | Some true, Some false ->
              Some
                ( "if c then true else false is longhand for c",
                  "use the condition",
                  true,
                  fun c -> c )
          | Some false, Some true ->
              Some
                ( "if c then false else true is longhand for not c",
                  "negate the condition",
                  false,
                  fun c -> "not " ^ c )
          | Some _, Some _ (* equal literals: degenerate *)
          | Some _, None
          | None, Some _
          | None, None ->
              None
        in
        match found with
        | None -> []
        | Some (m, title, safe, rewrite) ->
            let replace =
              if safe then Fix.safe_replace else Fix.unsafe_replace
            in
            let fix =
              Option.map
                (fun c ->
                  replace e.exp_loc (Unit.delimited u e (rewrite c)) ~title)
                (Unit.splice u c)
            in
            [ Finding.v ?fix ~loc:e.exp_loc m ])
