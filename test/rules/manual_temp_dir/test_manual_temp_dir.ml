(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_temp_dir.rule
let source = "fixtures/fix_mtd.ml"
let cmt = "fixtures/.fix_mtd.objs/byte/fix_mtd.cmt"

let () =
  Windtrap.run "manual-temp-dir"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-temp-dir" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked remove-then-mkdir sequences" (fun () ->
          Support.check_markers rule
            ~message:
              "removing a temp file to re-create its name as a directory \
               races; use Filename.temp_dir"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mtd.fixed.ml");
      test "the windowed and final shapes ship without a fix" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let fixless =
            List.filter
              (fun (_, f) -> Option.is_none (Litany.Finding.fix f))
              (Litany.Engine.Report.findings rep)
          in
          equal ~msg:"exactly two findings ship without a fix" int 2
            (List.length fixless));
    ]
