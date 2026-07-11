(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_tuple_matching.rule
let source = "fixtures/fix_mtm.ml"
let cmt = "fixtures/.fix_mtm.objs/byte/fix_mtm.cmt"

let () =
  Windtrap.run "manual-tuple-matching"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-tuple-matching" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked single irrefutable tuple cases"
        (fun () ->
          Support.check_markers rule
            ~message:"this match has one irrefutable case; bind it with let"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mtm.fixed.ml");
      test "the keyword-gap comment refuses the fix, not the finding" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let fixless =
            List.filter
              (fun (_, f) -> Option.is_none (Litany.Finding.fix f))
              (Litany.Engine.Report.findings rep)
          in
          equal ~msg:"exactly one finding ships without a fix" int 1
            (List.length fixless));
    ]
