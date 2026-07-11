(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Invalid_function_comparison.rule
let source = "fixtures/fix_ifc.ml"
let cmt = "fixtures/.fix_ifc.objs/byte/fix_ifc.cmt"

let () =
  Windtrap.run "invalid-function-comparison"
    [
      test "declares its one metadata record" (fun () ->
          equal string "invalid-function-comparison" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          equal string "1.0" (Rule.since rule));
      test "fires exactly on function operands of canonical comparisons"
        (fun () ->
          Support.check_markers rule
            ~message:"structural comparison has a function operand" ~source ~cmt);
    ]
