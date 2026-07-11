(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_catch_all_handler.rule
let source = "fixtures/fix_scah.ml"
let cmt = "fixtures/.fix_scah.objs/byte/fix_scah.cmt"

let () =
  Windtrap.run "suspicious-catch-all-handler"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-catch-all-handler" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable — graduated on reviewed field evidence"
            (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked wildcard handlers" (fun () ->
          Support.check_markers rule
            ~message:"wildcard handler swallows every exception" ~source ~cmt);
    ]
