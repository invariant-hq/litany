(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"used-underscore-binding" ~group:Rule.Suspicious
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"underscore-prefixed binding is used"
    ~doc:
      {|A leading underscore declares "this binding is intentionally unused"
and silences the compiler's unused warnings. Using the binding anyway
makes the name lie — and keeps the compiler from noticing when the
binding later becomes genuinely unused.

    (* bad *)  let _count = tally xs in report _count
    (* good *) let count = tally xs in report count

Fires once per binding, at the declaration, when a variable or alias
pattern binds a name beginning with exactly one underscore and the unit
uses that declaration anywhere — bare, or qualified through a module
path. The wildcard `_` binds nothing, names beginning with two
underscores follow a different convention, and unused underscore
bindings are the convention working as intended. A use through a
signature ascription carries the ascription's minted identity, not the
declaration's, and stays clean.

Tool-minted names stay clean even when used: `_1` and kin (an
underscore followed by
digits only — menhir's semantic values) and `…__NNN_` shapes (a name
ending in a double underscore, digits, and a final underscore —
jane-street ppx internals, `_of_a__001_`). Both are bound-and-used by
generated code as a calling convention, not a lie the author told; in
field review they were 99.9% of the rule's volume. Committed generated
sources carry them verbatim, so the name gate applies everywhere; the
generated-unit gate rides separately. Renaming is a
refactor, not a mechanical edit, so there is no fix.|}
    ()

let declares_unused name =
  String.length name > 1
  && Char.equal name.[0] '_'
  && not (Char.equal name.[1] '_')

let is_digit c = c >= '0' && c <= '9'

(* [_1], [_42]: a menhir semantic value — an underscore followed by
   digits only. *)
let menhir_value name =
  let rec digits i =
    i >= String.length name || (is_digit name.[i] && digits (i + 1))
  in
  String.length name > 1 && digits 1

(* [_of_a__001_], [_endpos__1_]: a ppx-minted internal — the name ends
   in a double underscore, one or more digits, and a final underscore. *)
let ppx_minted name =
  let n = String.length name in
  n >= 5
  && Char.equal name.[n - 1] '_'
  &&
  let rec run i =
    (* [i] scans the digit span leftward from [n - 2]; the span must be
       non-empty and preceded by two underscores. *)
    if i >= 2 && is_digit name.[i] then run (i - 1)
    else
      i <= n - 3
      && i >= 1
      && Char.equal name.[i] '_'
      && Char.equal name.[i - 1] '_'
  in
  run (n - 2)

let tool_minted name = menhir_value name || ppx_minted name

let rule =
  Rule.pattern meta @@ fun u p ->
  match Pat.bound_var p with
  | Some (name, uid)
    when declares_unused name.Location.txt
         && (not (tool_minted name.Location.txt))
         && Unit.uses u uid <> [] ->
      [ Finding.v ~loc:name.Location.loc "underscore-prefixed binding is used" ]
  | Some _ | None -> []
