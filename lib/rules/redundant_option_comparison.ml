(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-option-comparison" ~group:Rule.Pedantic
    ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"comparison with None spells an Option predicate"
    ~doc:
      {|`o = None` and `o <> None` are `Option.is_none o` and
`Option.is_some o` spelled through the polymorphic comparison. The
named predicates state the intent and survive a payload type turning
uncomparable. That is a preference, not a defect: the comparison is a
constant-time tag test either way, and `x = None` is common, idiomatic
OCaml — hence Pedantic. Adopt it where a codebase wants the predicate
spelling; `!r = None` reads at least as well as `Option.is_none !r`.

    (* bad *)  if o = None then default else run o
    (* good *) if Option.is_none o then default else run o

Fires when `=` or `<>` resolves to its `Stdlib` declaration with
exactly one operand the predefined `None` constructor, in either
position. Comparisons against `Some e` are out of scope entirely —
payload equality may deep-traverse and raise, and is a meaningful
program. `None = None` (a two-constant expression), orderings,
`compare`, physical equality, user-defined `None` lookalikes, and
shadowed operators deliberately do not fire. The fix rewrites the whole
comparison to the predicate applied to the other operand — structural
comparison against the immediate `None` decides on the tag without
traversing the payload, so the rewrite is behavior-identical, even for
payloads whose comparison would raise.

The reporting unit is the boolean chain, not the comparison: when two
or more such comparisons are direct operands of one `Stdlib` `&&`/`||`
chain (`s.arch <> None && s.layers <> None && s.rope <> None`), the
chain is one finding — anchored at
the whole chain, its fix rewriting every comparison at once — not one
per operand. A chain carrying exactly
one such comparison reports it as the standalone form does; a
comparison below anything other than a chain connective (an argument, a
`not`) keeps its own finding, and a rebound connective is no chain at
all. In preprocessed units the collapse is off and every comparison
reports individually: a rewriter-manufactured chain could anchor the
collapsed finding at a ghost location the emit contract drops,
silencing members that are real.|}
    ()

let eq = Pat.(apply (ident "Stdlib.(=)") (__ ^:: __ ^:: nil))
let ne = Pat.(apply (ident "Stdlib.(<>)") (__ ^:: __ ^:: nil))

(* The predefined [None] constructor expression by option identity
   ([Pat.enone]) — a
   same-spelling constructor of another type ([type t = None | Some of
   int]) has a different head type and stays clean. *)
let is_none u e = Pat.run Pat.enone u e () <> None

(* Exactly one [None] operand: [None = None] is a two-constant
   expression, a different smell (the redundant-boolean-comparison
   precedent), and zero leave nothing to rewrite. *)
let split u l r =
  match (is_none u l, is_none u r) with
  | true, false -> Some r
  | false, true -> Some l
  | true, true | false, false -> None

(* [comparison u e] is [Some (other, predicate)] when [e] is a
   None-comparison: the non-None operand, and the predicate the rewrite
   applies to it. *)
let comparison u e =
  match Pat.run eq u e (split u) with
  | Some (Some x) -> Some (x, "Option.is_none")
  | Some None | None -> (
      match Pat.run ne u e (split u) with
      | Some (Some x) -> Some (x, "Option.is_some")
      | Some None | None -> None)

(* A chain link: one [Stdlib.(&&)]/[Stdlib.(||)] application, exact
   arity. A rebound connective resolves elsewhere and is no chain,
   exactly as a rebound [=] is no comparison. *)
let link =
  Pat.(apply (idents [ "Stdlib.(&&)"; "Stdlib.(||)" ]) (__ ^:: __ ^:: nil))

let operands u e = Pat.run link u e (fun l r -> (l, r))

(* [members u e acc] prepends, in reverse source order, the
   None-comparison operands of the chain rooted at [e] — both connectives,
   both sides, nested links flattened. Any other operand is opaque: a
   comparison below it is not a member and keeps its own finding. *)
let rec members u e acc =
  match operands u e with
  | Some (l, r) -> members u r (members u l acc)
  | None -> (
      match comparison u e with
      | Some (x, predicate) -> ((e : Typedtree.expression), x, predicate) :: acc
      | None -> acc)

(* [link_operand u target] is [true] iff [target] is a direct operand of
   a chain link somewhere in [u]'s typedtree — the parent context the
   dispatch callback does not carry (quadratic-string-concat-chain
   decides by count; this rule needs the parent itself), recovered by a
   [Tast_iterator]
   walk of the same tree the engine dispatches ([Unit.implementation]),
   so physical identity decides. Pruned to expressions whose span
   encloses [target]'s — a ghost span cannot prune — and run only at the
   rare None-comparison and member-carrying-link nodes. *)
let link_operand u (target : Typedtree.expression) =
  let found = ref false in
  let encloses (outer : Location.t) =
    outer.loc_ghost
    || outer.loc_start.pos_cnum <= target.exp_loc.loc_start.pos_cnum
       && target.exp_loc.loc_end.pos_cnum <= outer.loc_end.pos_cnum
  in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub (ex : Typedtree.expression) ->
          if (not !found) && encloses ex.exp_loc then begin
            (match operands u ex with
            | Some (l, r) when l == target || r == target -> found := true
            | Some _ | None -> ());
            if not !found then default.expr sub ex
          end);
    }
  in
  iterator.structure iterator (Unit.implementation u);
  !found

let single u (e : Typedtree.expression) x predicate =
  let fix =
    Option.map
      (fun src ->
        Fix.safe_replace e.exp_loc
          (Unit.delimited u e (predicate ^ " " ^ src))
          ~title:("use " ^ predicate))
      (Unit.splice u x)
  in
  Finding.v ?fix ~loc:e.exp_loc
    ("comparison with None is longhand for " ^ predicate)

(* One finding for a chain of two or more members, anchored at the whole
   chain. The fix rewrites every member in one application, and ships
   only when every member's operand splices — a partial rewrite would
   leave a mixed chain while claiming Safe. *)
let chain u (e : Typedtree.expression) ms =
  let edits =
    List.map
      (fun ((m : Typedtree.expression), x, predicate) ->
        Option.map
          (fun src ->
            {
              Fix.span = Span.of_location m.exp_loc;
              text = Unit.delimited u m (predicate ^ " " ^ src);
            })
          (Unit.splice u x))
      ms
  in
  let fix =
    if List.for_all Option.is_some edits then
      Some
        (Fix.v ~applicability:Fix.Safe ~title:"use Option predicates"
           (List.filter_map Fun.id edits))
    else None
  in
  Finding.v ?fix ~loc:e.exp_loc
    (string_of_int (List.length ms)
    ^ " comparisons with None are longhand for Option predicates")

let rule =
  Rule.expr meta @@ fun u e ->
  match comparison u e with
  | Some (x, predicate) ->
      if (not (Unit.preprocessed u)) && link_operand u e then
        (* A chain member: the maximal link reports the chain. *)
        []
      else [ single u e x predicate ]
  | None -> (
      if Unit.preprocessed u then []
      else
        match operands u e with
        | None -> []
        | Some _ -> (
            match List.rev (members u e []) with
            | [] -> []
            | _ :: _ when link_operand u e ->
                (* An inner link: the maximal one reports. *)
                []
            | [ (m, x, predicate) ] -> [ single u m x predicate ]
            | ms -> [ chain u e ms ]))
