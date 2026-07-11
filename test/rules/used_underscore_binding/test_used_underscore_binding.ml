(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Used_underscore_binding.rule
let source = "fixtures/fix_uub.ml"
let cmt = "fixtures/.fix_uub.objs/byte/fix_uub.cmt"

let () =
  Windtrap.run "used-underscore-binding"
    [
      test "declares its one metadata record" (fun () ->
          equal string "used-underscore-binding" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked underscore-binding uses" (fun () ->
          Support.check_markers rule
            ~message:"underscore-prefixed binding is used" ~source ~cmt);
    ]
