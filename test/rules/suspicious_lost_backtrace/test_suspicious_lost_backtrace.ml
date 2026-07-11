(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_lost_backtrace.rule
let source = "fixtures/fix_slb.ml"
let cmt = "fixtures/.fix_slb.objs/byte/fix_slb.cmt"

let () =
  Windtrap.run "suspicious-lost-backtrace"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-lost-backtrace" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked working reraises" (fun () ->
          Support.check_markers rule
            ~message:
              "work before this reraise can overwrite the backtrace it \
               preserves; capture Printexc.get_raw_backtrace first and finish \
               with Printexc.raise_with_backtrace"
            ~source ~cmt);
    ]
