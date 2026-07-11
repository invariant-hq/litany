(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Restricted_global_mutable_state.rule
let source = "fixtures/fix_rgms.ml"
let cmt = "fixtures/.fix_rgms.objs/byte/fix_rgms.cmt"

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
  Windtrap.run "restricted-global-mutable-state"
    [
      test "declares its one metadata record" (fun () ->
          equal string "restricted-global-mutable-state" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked toplevel state in a library" (fun () ->
          Support.check_markers rule ~kind:Litany.Roster.Library
            ~message:
              "toplevel mutable state in a library is a process-wide global; \
               create it in the caller and pass it down"
            ~source ~cmt);
      test "an executable unit is silent" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Executable ~source ~cmt
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a test unit is silent" (fun () ->
          let rep = Support.report rule ~kind:Litany.Roster.Test ~source ~cmt in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a unit without kind metadata is silent" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
    ]
