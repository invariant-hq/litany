(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_exit_in_library.rule
let source = "fixtures/fix_seil.ml"
let cmt = "fixtures/.fix_seil.objs/byte/fix_seil.cmt"

(* The kind gate is roster metadata, so the suite builds its own entry
   per kind over the same fixture artifact — [Support.report] carries no
   kind, which is exactly the unknown-kind run. *)
let report ?kind () =
  let entry = Litany.Roster.Entry.v ~source ~cmt ?kind () in
  let resolver =
    Litany.Naming.Resolver.create
      ~cmi_dirs:[ Filename.dirname cmt; Config.standard_library ]
  in
  Litany.Engine.run ~rules:[ rule ] ~catalog:[ rule ]
    ~roster:(Litany.Roster.v [ entry ])
    ~load:(Litany.Unit.load ~resolver ~build_current:true)
    ()

let check_clean rep =
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep)

let finding_lines rep =
  List.map
    (fun (_, f) -> (Litany.Finding.loc f).Location.loc_start.Lexing.pos_lnum)
    (Litany.Engine.Report.findings rep)

let () =
  Windtrap.run "suspicious-exit-in-library"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-exit-in-library" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked references in a library" (fun () ->
          let rep = report ~kind:Litany.Roster.Library () in
          check_clean rep;
          List.iter
            (fun (_, f) ->
              equal ~msg:"message" string
                "exit in library code terminates the whole process"
                (Litany.Finding.message f))
            (Litany.Engine.Report.findings rep);
          equal ~msg:"finding lines vs (* FIRE *) markers" (list int)
            (Support.fire_lines ~source)
            (finding_lines rep));
      test "an executable unit is silent" (fun () ->
          let rep = report ~kind:Litany.Roster.Executable () in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a test unit is silent" (fun () ->
          let rep = report ~kind:Litany.Roster.Test () in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a unit without kind metadata is silent" (fun () ->
          let rep = report () in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
    ]
