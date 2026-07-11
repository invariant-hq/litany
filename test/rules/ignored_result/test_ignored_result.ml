(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Ignored_result.rule
let source = "fixtures/fix_ir.ml"
let cmt = "fixtures/.fix_ir.objs/byte/fix_ir.cmt"

let () =
  Windtrap.run "ignored-result"
    [
      test "declares its one metadata record" (fun () ->
          equal string "ignored-result" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked wildcard discards" (fun () ->
          Support.check_markers rule
            ~message:"result or option value is discarded by a wildcard binding"
            ~source ~cmt);
    ]
