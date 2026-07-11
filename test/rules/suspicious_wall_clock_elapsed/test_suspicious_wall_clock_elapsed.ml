(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_wall_clock_elapsed.rule
let source = "fixtures/fix_swce.ml"
let cmt = "fixtures/.fix_swce.objs/byte/fix_swce.cmt"

let () =
  Windtrap.run "suspicious-wall-clock-elapsed"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-wall-clock-elapsed" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked wall-clock arithmetic" (fun () ->
          Support.check_markers rule
            ~message:
              "elapsed-time arithmetic on a wall-clock read; use a monotonic \
               clock"
            ~source ~cmt);
    ]
