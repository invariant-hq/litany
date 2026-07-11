(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_guard_true.rule
let source = "fixtures/fix_rgt.ml"
let cmt = "fixtures/.fix_rgt.objs/byte/fix_rgt.cmt"
let always_true = "this guard is always true — drop it"
let always_false = "this guard is always false: the case never matches"

let () =
  Windtrap.run "redundant-guard-true"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-guard-true" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked literal guards" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each polarity carries its message" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              always_true;
              always_true;
              always_true;
              always_true;
              always_false;
              always_true;
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rgt.fixed.ml");
    ]
