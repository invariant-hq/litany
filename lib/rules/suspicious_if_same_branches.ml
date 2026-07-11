(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-if-same-branches" ~group:Rule.Suspicious
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"if whose two branches are written identically"
    ~doc:
      {|`if c then A else B` where `A` and `B` are the same bytes decides
nothing: either the condition is unnecessary or — more often — one
branch was meant to differ and a paste was never edited.

    (* bad *)  if is_admin u then grant u else grant u
    (* good *) if is_admin u then grant u else deny u

Fires when both branch slices of a non-preprocessed unit succeed and are
byte-identical after whitespace normalization (runs of spaces, tabs, and
newlines collapse to one space), and the condition is not a boolean
literal (suspicious-literal-condition owns those). Equality is the
source text, nothing deeper: branches differing only in a comment differ
in intent and do not fire, and `L.map` vs `List.map` — same resolution,
different spelling — is a deliberate false negative. Identical slices
imply identical effects, so no purity analysis is needed. No fix:
collapsing to one branch would bless the suspected copy-paste bug — the
author must decide which branch was meant to differ.|}
    ()

let message =
  "the two branches are identical — either the condition is unnecessary or one \
   branch was meant to differ"

let shape = Pat.(if_ __ __ (some __))
let literal_bool u e = Pat.run Pat.(ebool __) u e (fun _ -> ()) <> None

(* Normalized source-slice equality — the shared technique, from its one
   home. *)
let normalize = Normalized_slice.normalize
let slice = Normalized_slice.slice

(* The region between the branches must be exactly the [else] keyword:
   a comment there — `then f x (* retry path *) else f x` — sits outside
   both branch spans, where branch slices cannot see it, yet marks the
   arm that was meant to change. Anything but whitespace and [else] in
   the gap refuses (the nested-if fix's gap-verification technique). *)
let gap_is_else u (t : Typedtree.expression) (els : Typedtree.expression) =
  let start = Span.stop (Span.of_location t.exp_loc)
  and stop = Span.start (Span.of_location els.exp_loc) in
  start <= stop
  &&
  match Source.slice (Unit.source u) (Span.v ~start ~stop) with
  | Some gap -> String.equal (normalize gap) "else"
  | None -> false

let rule =
  Rule.expr meta @@ fun u e ->
  if Unit.preprocessed u then []
  else
    match
      Pat.run shape u e
        (fun c (t : Typedtree.expression) (els : Typedtree.expression) ->
          (c, t, els))
    with
    | None -> []
    | Some (c, t, els) -> (
        if literal_bool u c then []
        else
          match (slice u t.exp_loc, slice u els.exp_loc) with
          | Some a, Some b
            when String.equal (normalize a) (normalize b) && gap_is_else u t els
            ->
              [ Finding.v ~loc:e.exp_loc message ]
          | _ -> [])
