(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_physical_equality.rule
let source = "fixtures/fix_spe.ml"
let cmt = "fixtures/.fix_spe.objs/byte/fix_spe.cmt"

let () =
  Windtrap.run "suspicious-physical-equality"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-physical-equality" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable — confirmed on reviewed field evidence"
            (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          equal string "1.0" (Rule.since rule));
      test "fires exactly on proven non-immediate operands" (fun () ->
          Support.check_markers rule
            ~message:"physical comparison has a non-immediate operand" ~source
            ~cmt);
    ]
