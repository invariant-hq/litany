(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta ~closed_world =
  Rule.meta ~name:"dead-code" ~group:Rule.Suspicious
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"exported value unreachable from any root"
    ~doc:
      (Printf.sprintf
         {|An exported value no chain of live code reaches is dead: not used
directly, and every path that mentions it starts from something itself
dead. Where `unused-export` asks "does anyone name it", this rule
solves reachability — forward closure from the explicit roots — so a
group of units that only reference each other (a dead island, mutual
recursion included) is reported whole, exactly the case per-unit
analysis cannot see.

    (* bad *)  two units using only each other, reachable from no root
    (* good *) delete the island

Roots are explicit, computed from roster metadata: exports of public
(or unknown-visibility) libraries%s, the top level of executables and
tests, and `[@litany.root "reason"]` annotations. Granularity is the
export row: value declarations only, and intra-unit dependencies are
conservative — a live unit keeps every export its own implementation
references alive, so a value used only by a dead sibling of a live
unit is a recorded false negative, never a false positive. Unit-level
references keep the whole referenced unit provisionally live. The rule
runs only when every roster unit joined — one fact-skip withholds it
and the summary names the blockers. Workspaces built without
occurrence recording under-populate unit-level references. No fix:
deleting reachable-from-nowhere code is a
judgment about intent.|}
         (if closed_world then
            " (closed-world here: public exports are candidates)"
          else ""))
    ()

module Solver = Dead_code_solver

(* Synthetic solver nodes, two per unit, in the [Compilation_unit] namespace
   ([Solver.Uid.v]) so they can never collide with declaration ([Item]) UIDs:

   - [link U] — "U's code is linked and runs": root for executables/tests;
     reachable from any of U's exports (a used export links its unit); keeps
     U's own references (item rows, internal uses) live.
   - [all U] — "something reaches U without naming a declaration": the
     unit-level conservative arm; keeps every export of U provisionally
     live. *)
let link_uid unit_name = Solver.Uid.v ("link:" ^ unit_name)
let all_uid unit_name = Solver.Uid.v ("all:" ^ unit_name)

module M = Map.Make (struct
  type t = Shape.Uid.t

  let compare = Shape.Uid.compare
end)

let report facts =
  let decls = ref [] and edges = ref [] in
  let decl d = decls := d :: !decls in
  let edge ~user ~used = edges := Solver.Edge.v ~user ~used :: !edges in
  let units =
    List.filter_map
      (function
        | Project_facts.Unit_node { path; unit_name; root } ->
            Some (path, unit_name, root)
        | _ -> None)
      facts
  in
  (* target -> unit names a unit-level reference to [target] reaches,
     consulted by the [Use_unit] arm below: a lookup per row instead of a
     scan over all units keeps the phase linear in the fact universe
     (the naive scan measured quadratic — 4.4× per workspace doubling). *)
  let units_by_target : (string, string list) Hashtbl.t = Hashtbl.create 64 in
  List.iter
    (fun (path, unit_name, root) ->
      decl (Solver.Decl.v ~uid:(link_uid unit_name) ~owner:path ~root);
      decl (Solver.Decl.v ~uid:(all_uid unit_name) ~owner:path ~root:false);
      (* The conservative unit-level arm: [all U] frees every export. *)
      edge ~user:(all_uid unit_name) ~used:(link_uid unit_name);
      List.iter
        (fun target ->
          Hashtbl.replace units_by_target target
            (unit_name
            :: Option.value ~default:[]
                 (Hashtbl.find_opt units_by_target target)))
        (Project_facts.shield_targets unit_name))
    units;
  (* One solver declaration per uid: an include-re-export declares one
     interface uid through two units, which is one node — root iff any
     declaring row is, owned (for the solver's order and conflict check) by
     the first declaring row in fact order, edge-linked to every declaring
     unit. *)
  let grouped =
    List.fold_left
      (fun m -> function
        | Project_facts.Decl ({ uid; _ } as d) ->
            M.update uid
              (function None -> Some [ d ] | Some ds -> Some (d :: ds))
              m
        | _ -> m)
      M.empty facts
  in
  M.iter
    (fun uid rows ->
      let rows = List.rev rows in
      let first = List.hd rows in
      decl
        (Solver.Decl.v ~uid ~owner:first.Project_facts.path
           ~root:(List.exists (fun r -> r.Project_facts.root) rows));
      List.iter
        (fun (r : Project_facts.decl) ->
          (* A used export links each unit declaring it. *)
          edge ~user:uid ~used:(link_uid r.unit_name);
          (* Provisional liveness under a unit-level reference. *)
          edge ~user:(all_uid r.unit_name) ~used:uid;
          (* Intra-unit conservatism: a linked unit keeps the exports its
             own implementation references alive. *)
          if r.used_internally then edge ~user:(link_uid r.unit_name) ~used:uid)
        rows)
    grouped;
  List.iter
    (function
      | Project_facts.Use_item { user; uid } ->
          edge ~user:(link_uid user) ~used:uid
      | Project_facts.Use_unit { user; target } ->
          List.iter
            (fun unit_name ->
              edge ~user:(link_uid user) ~used:(all_uid unit_name))
            (Option.value ~default:[] (Hashtbl.find_opt units_by_target target))
      | Project_facts.Decl _ | Project_facts.Unit_node _ -> ())
    facts;
  let dead =
    List.fold_left
      (fun acc d ->
        let uid = Solver.Decl.uid d in
        if M.mem uid grouped then M.add uid () acc else acc
        (* synthetic link/all nodes are absent from [grouped] *))
      M.empty
      (Solver.unreachable ~decls:!decls ~edges:!edges)
  in
  (* One finding per declaring row of a dead uid, each at its own anchor —
     an include-re-exported dead value is dead at both declarations. *)
  List.filter_map
    (function
      | Project_facts.Decl { uid; loc; name; _ } when M.mem uid dead ->
          Some
            (Finding.v ~loc
               (Printf.sprintf "%s is never used in this workspace" name))
      | _ -> None)
    facts

let v ~closed_world =
  Rule.project (meta ~closed_world)
    ~collect:(Project_facts.collect ~closed_world)
    ~report

let rule = v ~closed_world:false
