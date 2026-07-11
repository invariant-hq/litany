(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_rec_without_recursion.rule
let source = "fixtures/fix_srwr.ml"
let cmt = "fixtures/.fix_srwr.objs/byte/fix_srwr.cmt"

let () =
  Windtrap.run "suspicious-rec-without-recursion"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-rec-without-recursion" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked inert let rec groups" (fun () ->
          Support.check_markers rule
            ~message:
              "rec is unused: no binding of this group references the group"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_srwr.fixed.ml");
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
