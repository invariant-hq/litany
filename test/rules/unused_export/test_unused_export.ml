(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Engine-end-to-end suite for the unused-export project rule, over a
   compiled multi-unit fixture workspace: one private unwrapped library
   (mli-backed units, an mli-side include re-export, a module ascription, a
   [@litany.root] annotation) plus one executable. *)

open Windtrap
module Support = Rules_test_support

let rule = Litany_rules.Unused_export.rule
let fx name = Filename.concat "fixtures" name
let obj name = Filename.concat "fixtures/.uexp.objs/byte" name

let units ?visibility () =
  [
    Support.project_unit ?visibility ~source:(fx "uexp_api.ml")
      ~cmt:(obj "uexp_api.cmt") ~cmti:(obj "uexp_api.cmti")
      ~interface_source:(fx "uexp_api.mli") ();
    Support.project_unit ?visibility ~source:(fx "uexp_lone.ml")
      ~cmt:(obj "uexp_lone.cmt") ~cmti:(obj "uexp_lone.cmti")
      ~interface_source:(fx "uexp_lone.mli") ();
    Support.project_unit ?visibility ~source:(fx "uexp_asc.ml")
      ~cmt:(obj "uexp_asc.cmt") ();
    Support.project_unit ?visibility ~source:(fx "uexp_sigs.ml")
      ~cmt:(obj "uexp_sigs.cmt") ~cmti:(obj "uexp_sigs.cmti")
      ~interface_source:(fx "uexp_sigs.mli") ();
    Support.project_unit ?visibility ~source:(fx "uexp_incl.ml")
      ~cmt:(obj "uexp_incl.cmt") ~cmti:(obj "uexp_incl.cmti")
      ~interface_source:(fx "uexp_incl.mli") ();
    Support.project_unit ~source:(fx "uexp_main.ml")
      ~cmt:"fixtures/.uexp_main.eobjs/byte/dune__exe__Uexp_main.cmt"
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

let metadata =
  group "metadata"
    [
      test "declaration" (fun () ->
          equal ~msg:"name" string "unused-export" (Litany.Rule.name rule);
          equal ~msg:"group" string "suspicious"
            (Litany.Rule.Group.to_string (Litany.Rule.group rule));
          equal ~msg:"stability" string "nursery"
            (Litany.Rule.Stability.to_string (Litany.Rule.stability rule));
          equal ~msg:"since" string "1.0" (Litany.Rule.since rule);
          is_true ~msg:"fix never" (Litany.Rule.fix rule = Litany.Rule.Never);
          is_true ~msg:"is_project" (Litany.Rule.is_project rule);
          is_false ~msg:"nursery is off by default"
            (Litany.Rule.on_by_default rule));
    ]

let findings =
  group "findings"
    [
      test "the exact conservative set" (fun () ->
          (* Fires: the mli-anchored export of a unit nothing references, and
           the minted ascription identity of another. Silent, each pinned by
           absence: uexp_api.unused (unit-level shield — uexp_main
           references Uexp_api), uexp_incl.v / the include's origin (used by
           uexp_main under the foreign interface identity), kept
           ([@litany.root]), and every export of the executable (it has
           none). *)
          let rep = Support.project_report [ rule ] (units ()) in
          no_failures rep;
          equal ~msg:"status" string "ran" (status rep);
          equal ~msg:"findings"
            (list (quad string string int string))
            [
              ( "unused-export",
                fx "uexp_asc.ml",
                2,
                "Asc.length is exported but never used by another unit in this \
                 workspace" );
              ( "unused-export",
                fx "uexp_lone.mli",
                1,
                "alone is exported but never used by another unit in this \
                 workspace" );
            ]
            (view rep));
      test "roster order does not matter" (fun () ->
          let rep = Support.project_report [ rule ] (List.rev (units ())) in
          no_failures rep;
          equal ~msg:"findings under reversed roster"
            (list (quad string string int string))
            (view (Support.project_report [ rule ] (units ())))
            (view rep));
    ]

let world =
  group "root policy"
    [
      test "public visibility roots everything (open world)" (fun () ->
          let rep =
            Support.project_report [ rule ]
              (units ~visibility:Litany.Roster.Public ())
          in
          no_failures rep;
          equal ~msg:"no candidates in a public library"
            (list (quad string string int string))
            [] (view rep));
      test "closed-world makes public exports candidates" (fun () ->
          let closed = Litany_rules.Unused_export.v ~closed_world:true in
          let rep =
            Support.project_report [ closed ]
              (units ~visibility:Litany.Roster.Public ())
          in
          no_failures rep;
          equal ~msg:"same findings as the private run" (list string)
            (List.map
               (fun (_, _, _, m) -> m)
               (view (Support.project_report [ rule ] (units ()))))
            (List.map (fun (_, _, _, m) -> m) (view rep)));
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
          (match Litany.Engine.Report.project_rules rep with
          | [ (_, Some (Litany.Engine.Report.Incomplete blocking)) ] ->
              equal ~msg:"the blocker is named" (list string)
                [ fx "broken.ml" ]
                (List.map fst blocking)
          | _ -> is_true ~msg:"incomplete carries blockers" false);
          equal ~msg:"no project findings when withheld"
            (list (quad string string int string))
            [] (view rep));
      test "an incomplete roster is unavailable" (fun () ->
          let rep =
            Support.project_report ~complete:false [ rule ] (units ())
          in
          no_failures rep;
          equal ~msg:"status" string "unavailable" (status rep);
          equal ~msg:"no findings"
            (list (quad string string int string))
            [] (view rep));
      test "a failing collect blocks that rule alone, units named" (fun () ->
          (* The per-rule arm of the disposition algebra: a raising
             [collect] holes one rule's universe — its report is blocked
             ([Collect_failed], the failure rows are the exit-3 record) —
             while a healthy project rule beside it still runs over the
             complete universe. *)
          let boom =
            Litany.Rule.project
              (Litany.Rule.meta ~name:"boom-collect"
                 ~group:Litany.Rule.Suspicious ~since:"1.0"
                 ~fix:Litany.Rule.Never ~summary:"test rule" ~doc:"test rule" ())
              ~collect:(fun _ -> failwith "collect boom")
              ~report:(fun _ -> [])
          in
          let rep = Support.project_report [ rule; boom ] (units ()) in
          (match Litany.Engine.Report.project_rules rep with
          | [
           ("unused-export", None);
           ("boom-collect", Some (Litany.Engine.Report.Collect_failed paths));
          ] ->
              equal ~msg:"every admitted unit is a named hole" (list string)
                (List.map fst (Litany.Engine.Report.units rep))
                paths
          | _ ->
              is_true ~msg:"healthy rule ran; failing rule blocked alone" false);
          is_true ~msg:"the healthy rule's findings stand" (view rep <> []);
          equal ~msg:"the failures are the loud record (exit 3)" int 3
            (Litany.Engine.Report.exit_code rep));
      test "duplicate unit names are engine-detected ambiguity, named"
        (fun () ->
          (* A byte-identical copy of uexp_lone.ml against the original's
             cmt gives Uexp_lone two distinct declaring paths: the
             name-keyed use joins are then ambiguous (a same-named sibling
             silently shields — the false-negative lane), so the
             engine tabulates admitted names itself and blocks the report
             with the duplicate named instead of reporting 0 findings. *)
          let dup =
            Support.project_unit ~source:(fx "uexp_lone_dup.ml")
              ~cmt:(obj "uexp_lone.cmt") ()
          in
          let rep = Support.project_report [ rule ] (units () @ [ dup ]) in
          no_failures rep;
          equal ~msg:"status" string "ambiguous" (status rep);
          (match Litany.Engine.Report.project_rules rep with
          | [ ("unused-export", Some (Litany.Engine.Report.Ambiguous dups)) ] ->
              equal ~msg:"the duplicate is named, paths in roster order"
                (list (pair string (list string)))
                [ ("Uexp_lone", [ fx "uexp_lone.ml"; fx "uexp_lone_dup.ml" ]) ]
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

let () = run "unused-export" [ metadata; findings; world; honesty; facts ]
