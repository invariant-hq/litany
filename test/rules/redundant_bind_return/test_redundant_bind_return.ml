(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_bind_return.rule
let source = "fixtures/fix_rbr.ml"
let cmt = "fixtures/.fix_rbr.objs/byte/fix_rbr.cmt"

let () =
  Windtrap.run "redundant-bind-return"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-bind-return" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked bare-return binds" (fun () ->
          Support.check_markers rule
            ~message:
              "binding into a bare return re-wraps the value; use the \
               computation directly"
            ~source ~cmt);
    ]
