(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_case_guard.rule
let source = "fixtures/fix_mcg.ml"
let cmt = "fixtures/.fix_mcg.objs/byte/fix_mcg.cmt"

let () =
  Windtrap.run "manual-case-guard"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-case-guard" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked immediate ifs" (fun () ->
          Support.check_markers rule
            ~message:
              "an immediate if-then-else in a case body could be a when guard"
            ~source ~cmt);
    ]
