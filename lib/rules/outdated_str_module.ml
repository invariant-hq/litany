(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"outdated-str-module" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never ~summary:"reference into the outdated Str module"
    ~doc:
      {|`Str` funnels every match through one global state: each
`Str.string_match` stores its groups in hidden cells that the next match —
from any thread — silently overwrites, so `Str.matched_group` answers for
whichever match ran last.

    (* bad *)  Str.string_match (Str.regexp "a+") s 0
    (* good *) Re.execp (Re.compile Re.(rep1 (char 'a'))) s

Fires once per referenced `Str` declaration per unit: every reference
to a value declared in the `Str` compilation unit — spelled directly,
through an alias, or via `open` — joins its declaration's cluster, and
the cluster is one finding anchored at the first reference, its
message carrying the count (`Str.matched_group referenced 30 times in
this unit`); a declaration referenced once keeps the plain message. A
project-local `module Str`, a functor parameter named `Str`, a value
named `str`, and `Re.Str` (Re's compatibility layer, declared in Re's
own units and a fine migration vehicle) deliberately do not fire; a
vendored unit literally named `Str` does, because the compilation unit
is the identity boundary. In preprocessed units the collapse is off
and every reference reports individually: a rewriter-spliced location
on a cluster's first reference is one the emit contract drops, and
dropping the anchor would silence references that are real. Off by
default even after graduation — adopting Re is a dependency decision —
and no fix: the rewrite is a migration.

Stable on field evidence: zero false positives over 91 reviewed
sightings, UID-based with no resolver dependence. The per-reference
walls that review recorded — one Str-heavy unit answering a dense page
of findings — are what the collapse retires: each referenced
declaration now reports once per unit.|}
    ()

(* The unit name on the use site's declaration UID is the whole test —
   [Pat.from_unit]'s contract: no canonical-name resolution, so a
   workspace without str linked simply never sees the unit. *)
let str_reference = Pat.from_unit "Str"
let message = "Str answers matches through global state; use Re"

(* [spelled u uid] is the non-ghost use sites of [uid] in [u], in
   traversal order — the cluster a finding speaks for. Ghost uses are
   synthesized, not spelled: they neither anchor (the emit contract
   drops a ghost anchor, and one drop would silence the cluster) nor
   count (the message counts references the author can read). *)
let spelled u uid =
  List.filter (fun (l : Location.t) -> not l.loc_ghost) (Unit.uses u uid)

let rule =
  Rule.expr meta @@ fun u e ->
  match e.exp_desc with
  | Typedtree.Texp_ident (path, _, vd) when Pat.run str_reference u e () <> None
    ->
      if Unit.preprocessed u then
        (* Collapse off: locations a rewriter spliced cannot be trusted
           to anchor a whole cluster — the roc precedent — so every
           reference stands on its own location, kept or dropped
           individually. *)
        [ Finding.v ~loc:e.exp_loc message ]
      else
        begin match spelled u vd.Types.val_uid with
        | anchor :: _ when anchor <> e.exp_loc ->
            (* A later reference of the cluster: the first reports. *)
            []
        | _ :: _ :: _ as cluster ->
            (* The cluster key is the declaration UID, so the message
               names the declaration — [Str.quote] even when the anchor
               spells it through an alias. *)
            [
              Finding.v ~loc:e.exp_loc
                ("Str." ^ Path.last path ^ " referenced "
                ^ string_of_int (List.length cluster)
                ^ " times in this unit; " ^ message);
            ]
        | [ _ ] | [] ->
            (* One spelled reference — the plain form; [[]] only when
               [e] itself is ghost and unindexed, and the emit contract
               drops the finding either way. *)
            [ Finding.v ~loc:e.exp_loc message ]
        end
  | _ -> []
