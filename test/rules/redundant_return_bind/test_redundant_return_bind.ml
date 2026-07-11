(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_return_bind.rule
let source = "fixtures/fix_rrb.ml"
let cmt = "fixtures/.fix_rrb.objs/byte/fix_rrb.cmt"

let () =
  Windtrap.run "redundant-return-bind"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-return-bind" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked fresh-return binds" (fun () ->
          Support.check_markers rule
            ~message:
              "binding a fresh return wraps a value only to unwrap it; apply \
               the callback directly"
            ~source ~cmt);
    ]
