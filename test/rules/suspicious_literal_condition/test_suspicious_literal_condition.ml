(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_literal_condition.rule
let source = "fixtures/fix_slc.ml"
let cmt = "fixtures/.fix_slc.objs/byte/fix_slc.cmt"

let () =
  Windtrap.run "suspicious-literal-condition"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-literal-condition" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked literal conditions" (fun () ->
          (* The message names the literal, so no single expected message. *)
          Support.check_markers rule ~source ~cmt);
    ]
