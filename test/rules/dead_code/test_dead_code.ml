(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Engine-end-to-end suite for the dead-code project rule, over a compiled
   multi-unit fixture workspace: a private unwrapped library holding a dead
   island (dci_a -> dci_b, dci_a -> dcx_lone) and intra-unit recursive
   cycles (dci_self), plus the executable root that keeps dcx_used alive. *)

open Windtrap
module Support = Rules_test_support

let rule = Litany_rules.Dead_code.rule
let fx name = Filename.concat "fixtures" name
let obj name = Filename.concat "fixtures/.dcx.objs/byte" name

let units ?visibility () =
  [
    Support.project_unit ?visibility ~source:(fx "dcx_used.ml")
      ~cmt:(obj "dcx_used.cmt") ~cmti:(obj "dcx_used.cmti")
      ~interface_source:(fx "dcx_used.mli") ();
    Support.project_unit ?visibility ~source:(fx "dcx_lone.ml")
      ~cmt:(obj "dcx_lone.cmt") ~cmti:(obj "dcx_lone.cmti")
      ~interface_source:(fx "dcx_lone.mli") ();
    Support.project_unit ?visibility ~source:(fx "dci_a.ml")
      ~cmt:(obj "dci_a.cmt") ~cmti:(obj "dci_a.cmti")
      ~interface_source:(fx "dci_a.mli") ();
    Support.project_unit ?visibility ~source:(fx "dci_b.ml")
      ~cmt:(obj "dci_b.cmt") ~cmti:(obj "dci_b.cmti")
      ~interface_source:(fx "dci_b.mli") ();
    Support.project_unit ?visibility ~source:(fx "dci_self.ml")
      ~cmt:(obj "dci_self.cmt") ();
    Support.project_unit ~source:(fx "dcx_root.ml")
      ~cmt:"fixtures/.dcx_root.eobjs/byte/dune__exe__Dcx_root.cmt"
      ~kind:Litany.Roster.Executable ();
  ]

let view rep =
  List.map
    (fun (rule, f) ->
      let l = Litany.Finding.loc f in
      ( rule,
        l.Location.loc_start.pos_fname,
        l.Location.loc_start.pos_lnum,
        Litany.Finding.message f ))
    (Litany.Engine.Report.findings rep)

let no_failures rep =
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep))

let status rep =
  (* One project rule per suite run: its disposition is the run's story. *)
  match Litany.Engine.Report.project_rules rep with
  | [ (_, None) ] -> "ran"
  | [ (_, Some Litany.Engine.Report.Not_capable) ] -> "unavailable"
  | [ (_, Some (Litany.Engine.Report.Incomplete _)) ] -> "withheld"
  | [ (_, Some (Litany.Engine.Report.Ambiguous _)) ] -> "ambiguous"
  | [ (_, Some (Litany.Engine.Report.Collect_failed _)) ] -> "collect-failed"
  | _ -> "unexpected"

let dead name = name ^ " is never used in this workspace"

let metadata =
  group "metadata"
    [
      test "declaration" (fun () ->
          equal ~msg:"name" string "dead-code" (Litany.Rule.name rule);
          equal ~msg:"group" string "suspicious"
            (Litany.Rule.Group.to_string (Litany.Rule.group rule));
          equal ~msg:"stability" string "nursery"
            (Litany.Rule.Stability.to_string (Litany.Rule.stability rule));
          equal ~msg:"since" string "1.0" (Litany.Rule.since rule);
          is_true ~msg:"fix never" (Litany.Rule.fix rule = Litany.Rule.Never);
          is_true ~msg:"is_project" (Litany.Rule.is_project rule));
    ]

let findings =
  group "findings"
    [
      test "reachability from the roots, islands whole" (fun () ->
          (* Fires: the island top (ping), its transitively-dead uses (pong,
           alone), the intra-unit recursive cycles (loop, odd, even — the
           provisional-dead cases, reported whole), and the executable's own
           dead export. Silent, pinned by absence: entry (used by the root),
           spare (the conservative unit-level shield — dcx_root references
           Dcx_used), rooted_keep ([@litany.root]), live_helper (the
           executable's own top level runs it). *)
          let rep = Support.project_report [ rule ] (units ()) in
          no_failures rep;
          equal ~msg:"status" string "ran" (status rep);
          equal ~msg:"findings"
            (list (quad string string int string))
            [
              ("dead-code", fx "dci_a.mli", 1, dead "ping");
              ("dead-code", fx "dci_b.mli", 1, dead "pong");
              ("dead-code", fx "dci_self.ml", 3, dead "loop");
              ("dead-code", fx "dci_self.ml", 5, dead "odd");
              ("dead-code", fx "dci_self.ml", 6, dead "even");
              ("dead-code", fx "dcx_lone.mli", 1, dead "alone");
              ("dead-code", fx "dcx_root.ml", 2, dead "dead_helper");
            ]
            (view rep));
      test "roster order does not matter" (fun () ->
          let rep = Support.project_report [ rule ] (List.rev (units ())) in
          no_failures rep;
          equal ~msg:"findings under reversed roster"
            (list (quad string string int string))
            (view (Support.project_report [ rule ] (units ())))
            (view rep));
      test "public visibility roots the library; closed-world reopens it"
        (fun () ->
          let rep =
            Support.project_report [ rule ]
              (units ~visibility:Litany.Roster.Public ())
          in
          no_failures rep;
          (* Only the executable's own export stays a candidate. *)
          equal ~msg:"open world, public library"
            (list (quad string string int string))
            [ ("dead-code", fx "dcx_root.ml", 2, dead "dead_helper") ]
            (view rep);
          let closed = Litany_rules.Dead_code.v ~closed_world:true in
          let rep =
            Support.project_report [ closed ]
              (units ~visibility:Litany.Roster.Public ())
          in
          no_failures rep;
          equal ~msg:"closed world restores the full set" (list string)
            (List.map
               (fun (_, _, _, m) -> m)
               (view (Support.project_report [ rule ] (units ()))))
            (List.map (fun (_, _, _, m) -> m) (view rep)));
    ]

let contrast =
  group "against unused-export"
    [
      test "transitivity is the difference" (fun () ->
          (* One run, both rules: unused-export sees direct use only, so pong
           and alone (used by the dead island) are its negatives while
           dead-code reports them, and the executable's dead_helper is
           dead-code's alone (an executable has no interface surface); the
           never-referenced library decls (ping, the dci_self cycles) are
           reported by both. *)
          let rep =
            Support.project_report
              [ rule; Litany_rules.Unused_export.rule ]
              (units ())
          in
          no_failures rep;
          let by_rule name =
            List.filter_map
              (fun (r, p, l, _) ->
                if String.equal r name then Some (p, l) else None)
              (view rep)
          in
          equal ~msg:"dead-code set"
            (list (pair string int))
            [
              (fx "dci_a.mli", 1);
              (fx "dci_b.mli", 1);
              (fx "dci_self.ml", 3);
              (fx "dci_self.ml", 5);
              (fx "dci_self.ml", 6);
              (fx "dcx_lone.mli", 1);
              (fx "dcx_root.ml", 2);
            ]
            (by_rule "dead-code");
          equal ~msg:"unused-export set (no pong, no alone, no executable)"
            (list (pair string int))
            [
              (fx "dci_a.mli", 1);
              (fx "dci_self.ml", 3);
              (fx "dci_self.ml", 5);
              (fx "dci_self.ml", 6);
            ]
            (by_rule "unused-export"));
    ]

let honesty =
  group "withhold"
    [
      test "one fact-skip withholds the report" (fun () ->
          let broken =
            Support.project_unit ~source:(fx "broken.ml")
              ~cmt:(fx "no-such.cmt") ()
          in
          let rep = Support.project_report [ rule ] (units () @ [ broken ]) in
          no_failures rep;
          equal ~msg:"status" string "withheld" (status rep);
          equal ~msg:"no findings when withheld"
            (list (quad string string int string))
            [] (view rep));
      test "an incomplete roster is unavailable" (fun () ->
          let rep =
            Support.project_report ~complete:false [ rule ] (units ())
          in
          no_failures rep;
          equal ~msg:"status" string "unavailable" (status rep));
      test "duplicate unit names are engine-detected ambiguity, named"
        (fun () ->
          (* Compilation unit names are not workspace-unique (two
             executables both named main.ml); a byte-identical copy of
             dcx_lone.ml against the original's cmt admits fine and gives
             Dcx_lone two distinct declaring paths. The run must neither
             fail (exit 3) nor report over the collapsed identity: the
             engine tabulates admitted names itself and blocks the report
             with the duplicate named. *)
          let dup =
            Support.project_unit ~source:(fx "dcx_lone_dup.ml")
              ~cmt:(obj "dcx_lone.cmt") ()
          in
          let rep = Support.project_report [ rule ] (units () @ [ dup ]) in
          no_failures rep;
          equal ~msg:"status" string "ambiguous" (status rep);
          (match Litany.Engine.Report.project_rules rep with
          | [ ("dead-code", Some (Litany.Engine.Report.Ambiguous dups)) ] ->
              equal ~msg:"the duplicate is named, paths in roster order"
                (list (pair string (list string)))
                [ ("Dcx_lone", [ fx "dcx_lone.ml"; fx "dcx_lone_dup.ml" ]) ]
                dups
          | _ -> is_true ~msg:"exactly one ambiguous disposition" false);
          equal ~msg:"no findings under a collapsed identity"
            (list (quad string string int string))
            [] (view rep));
    ]

let facts =
  group "facts"
    [
      test "Marshal round-trip (the Marshal-safety law)" (fun () ->
          Support.check_project_marshal rule (units ()));
    ]

let () = run "dead-code" [ metadata; findings; contrast; honesty; facts ]
