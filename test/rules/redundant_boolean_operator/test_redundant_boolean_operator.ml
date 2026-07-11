(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_boolean_operator.rule
let source = "fixtures/fix_rbo.ml"
let cmt = "fixtures/.fix_rbo.objs/byte/fix_rbo.cmt"

let () =
  Windtrap.run "redundant-boolean-operator"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-boolean-operator" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked constant operands" (fun () ->
          Support.check_markers rule
            ~message:"boolean operator has a redundant constant operand" ~source
            ~cmt);
    ]
