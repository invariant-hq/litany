(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-rec-without-recursion" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"let rec group that never recurses"
    ~doc:
      {|A `let rec` whose bindings never reference the group is wearing a
costume: the reader budgets for recursion that never happens, and the
`rec` silently changes which same-named outer bindings the bodies see.
The compiler's warning 39 makes the same judgment — off in the vanilla
compiler, an error under dune's dev profile, so this rule's yield is
non-dune workspaces and permissive configurations — but cannot repair
it.

    (* bad *)  let rec parse s = lex s in parse input
    (* good *) let parse s = lex s in parse input

Fires once per `let rec` group — structure-level items and
expression-level `let … in` alike — none of whose bindings references
any binding of the group, proved by declaration identity: a use of a
group identity anywhere inside a group body blocks the finding however
deeply nested, while a same-spelled inner rebinding is a different
identity and never counts. Uses after the group — in the `in` body or
later in the unit — do not block; they are what the binding is for.
Partially recursive groups (`let rec f x = f x and g y = y`) never
fire: dropping `rec` is not their remedy, splitting the group is.
Class-body groups are a recorded false negative — the group dispatch
does not see them. The fix deletes the `rec`
keyword when the unit is not preprocessed and exactly whitespace,
`let`, whitespace, `rec`, whitespace separates the group start from
its first pattern — an attribute or comment there refuses the fix,
never the finding. The identity proof is what makes the deletion safe:
no body resolves any group name, so removing those names from the
bodies' scope retargets nothing.|}
    ()

let message = "rec is unused: no binding of this group references the group"

let span_of_loc (loc : Location.t) =
  let start = loc.Location.loc_start.Lexing.pos_cnum
  and stop = loc.Location.loc_end.Lexing.pos_cnum in
  if start < 0 || stop < start then None else Some (Span.v ~start ~stop)

(* The group is inert iff every binding's pattern is a variable (all
   `let rec` admits) and no use of any bound identity lands inside any
   group body. A use whose location cannot be placed is treated as a
   group reference — refusal, never a guess. *)
let inert u vbs =
  let rec bound acc = function
    | [] -> Some (List.rev acc)
    | vb :: rest -> (
        match Pat.bound_var vb.Typedtree.vb_pat with
        | Some (_, uid) -> bound (uid :: acc) rest
        | None -> None)
  in
  let rec bodies acc = function
    | [] -> Some (List.rev acc)
    | vb :: rest -> (
        match span_of_loc vb.Typedtree.vb_expr.exp_loc with
        | Some sp -> bodies (sp :: acc) rest
        | None -> None)
  in
  match (bound [] vbs, bodies [] vbs) with
  | Some uids, Some spans ->
      let outside loc =
        match span_of_loc loc with
        | None -> false
        | Some use -> not (List.exists (fun sp -> Span.includes sp use) spans)
      in
      List.for_all (fun uid -> List.for_all outside (Unit.uses u uid)) uids
  | _, _ -> false

(* [keyword_gap s] is [true] iff [s] is optional whitespace, `let`,
   whitespace, `rec`, whitespace — the exact keyword gap between the
   group start and its first pattern. Anything else there (an
   attribute, a comment) refuses the fix. *)
let keyword_gap s =
  let n = String.length s in
  let is_ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let rec ws i = if i < n && is_ws s.[i] then ws (i + 1) else i in
  let word w i =
    let m = String.length w in
    if i + m <= n && String.equal (String.sub s i m) w then Some (i + m)
    else None
  in
  match word "let" (ws 0) with
  | None -> false
  | Some i -> (
      let j = ws i in
      j > i
      &&
      match word "rec" j with
      | None -> false
      | Some k ->
          let l = ws k in
          l > k && l = n)

let drop_rec u (group : Location.t) (first_pat : Location.t) =
  if Unit.preprocessed u then None
  else
    let start = group.Location.loc_start.Lexing.pos_cnum
    and stop = first_pat.Location.loc_start.Lexing.pos_cnum in
    if start < 0 || stop < start then None
    else
      let span = Span.v ~start ~stop in
      let src = Unit.source u in
      match Source.slice src span with
      | Some s when keyword_gap s ->
          Option.map
            (fun loc -> Fix.safe_replace loc "let " ~title:"drop rec")
            (Source.location src span)
      | Some _ | None -> None

let rule =
  Rule.let_group meta @@ fun u ~loc rf vbs ->
  match (rf, vbs) with
  | Asttypes.Recursive, first :: _ when inert u vbs ->
      let anchor = first.Typedtree.vb_pat.pat_loc in
      let fix = drop_rec u loc anchor in
      [ Finding.v ?fix ~loc:anchor message ]
  | _, _ -> []
