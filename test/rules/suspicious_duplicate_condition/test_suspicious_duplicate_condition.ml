(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_duplicate_condition.rule
let source = "fixtures/fix_sdc.ml"
let cmt = "fixtures/.fix_sdc.objs/byte/fix_sdc.cmt"

let message =
  "this condition duplicates the previous arm's — the arm can never run"

let () =
  Windtrap.run "suspicious-duplicate-condition"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-duplicate-condition" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked duplicated conditions" (fun () ->
          Support.check_markers ~message rule ~source ~cmt);
    ]
