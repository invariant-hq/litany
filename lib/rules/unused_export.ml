(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta ~closed_world =
  Rule.meta ~name:"unused-export" ~group:Rule.Suspicious
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"exported value never used by another unit"
    ~doc:
      (Printf.sprintf
         {|An exported value no other unit of the workspace references is
surface a maintainer must read, document, and keep compiling for
nobody. The finding anchors at the declaration — the `.mli` line when
the unit has one — and the claim is exact and non-transitive: the
value is used by no *other* unit, counting nothing about whether its
users are themselves alive (that judgment is `dead-code`'s).

    (* bad *)  val helper : int -> int   (* no other unit mentions it *)
    (* good *) delete the export (and the binding, if nothing local uses it)

Roots are never candidates: exports of public (or unknown-visibility)
libraries — external consumers exist outside every universe litany can
enumerate%s — and declarations annotated `[@litany.root "reason"]`.
Executables and tests have no interface surface, so their values are
never candidates (`dead-code` covers them). Value declarations only:
types and modules have no always-on cross-unit use signal, so 1.0
stays silent on them rather than guess.
A unit-level reference (a use the compiler recorded against the unit
without pinning a declaration) conservatively shields every export of
the referenced unit. Cross-module honesty: the rule runs only when
every roster unit joined — one fact-skip withholds it, and the summary
names the blockers. Workspaces built without occurrence recording
under-populate unit-level references; module-alias-only and
functor-argument uses can then be missed in the shielding direction —
a recorded nursery caveat. No fix: deleting an
export is an interface decision.|}
         (if closed_world then
            " (this catalog was configured closed-world: public exports are \
             candidates)"
          else ""))
    ()

(* The non-transitive judgment (fewer, harder findings first): a
   non-root export is unused iff no *other* unit's item-level rows carry its
   UID and no other unit has a unit-level row reaching its owner. Every join
   below is a table built in one pass over the facts and answered by lookup,
   so the phase is linear in the fact universe (the naive
   decl × use-row scan measured quadratic — 4.4× per workspace doubling). *)
let report facts =
  let module M = Map.Make (struct
    type t = Shape.Uid.t

    let compare = Shape.Uid.compare
  end) in
  (* uid -> using unit names (item-level). *)
  let item_users =
    List.fold_left
      (fun m -> function
        | Project_facts.Use_item { user; uid } ->
            M.update uid
              (function None -> Some [ user ] | Some us -> Some (user :: us))
              m
        | _ -> m)
      M.empty facts
  in
  (* target -> referencing unit names (unit-level rows), consulted through
     each declaring unit's [shield_targets]. *)
  let refs_by_target : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  (* Units whose top level is a product root (executables, tests): their
     values are not interface surface — nothing can link against an
     executable module — so they are never unused-export candidates.
     [dead-code] still covers them. *)
  let product_units : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (function
      | Project_facts.Use_unit { user; target } ->
          Hashtbl.replace refs_by_target target
            (user
            :: Option.value ~default:[] (Hashtbl.find_opt refs_by_target target)
            )
      | Project_facts.Unit_node { unit_name; root = true; _ } ->
          Hashtbl.replace product_units unit_name ()
      | Project_facts.Unit_node _ | Project_facts.Decl _
      | Project_facts.Use_item _ ->
          ())
    facts;
  List.filter_map
    (function
      | Project_facts.Decl { unit_name; uid; name; loc; root; _ }
        when not (Hashtbl.mem product_units unit_name) ->
          let used_by_other =
            (match M.find_opt uid item_users with
              | Some users ->
                  List.exists (fun u -> not (String.equal u unit_name)) users
              | None -> false)
            || List.exists
                 (fun target ->
                   match Hashtbl.find_opt refs_by_target target with
                   | None -> false
                   | Some users ->
                       List.exists
                         (fun u -> not (String.equal u unit_name))
                         users)
                 (Project_facts.shield_targets unit_name)
          in
          if root || used_by_other then None
          else
            Some
              (Finding.v ~loc
                 (Printf.sprintf
                    "%s is exported but never used by another unit in this \
                     workspace"
                    name))
      | _ -> None)
    facts

let v ~closed_world =
  Rule.project (meta ~closed_world)
    ~collect:(Project_facts.collect ~closed_world)
    ~report

let rule = v ~closed_world:false
