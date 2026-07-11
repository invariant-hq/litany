(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_record_update.rule
let source = "fixtures/fix_mru.ml"
let cmt = "fixtures/.fix_mru.objs/byte/fix_mru.cmt"

let () =
  Windtrap.run "manual-record-update"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-record-update" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual rebuilds" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "messages name the base and the remedy" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let messages =
            List.map
              (fun (_, f) -> Litany.Finding.message f)
              (Litany.Engine.Report.findings rep)
          in
          equal (list string)
            [
              "this record rebuilds r field by field; it is r itself";
              "copy the base with { r with z = ... }";
              "copy the base with { r with z = ... }";
              "copy the base with { M.default with z = ... }";
            ]
            messages);
    ]
