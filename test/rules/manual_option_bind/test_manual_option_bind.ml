(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_option_bind.rule
let source = "fixtures/fix_mob.ml"
let cmt = "fixtures/.fix_mob.objs/byte/fix_mob.cmt"

let message =
  "manual match re-implements Option.bind — use Option.bind o (fun y -> …)"

let () =
  Windtrap.run "manual-option-bind"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-option-bind" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual binds" (fun () ->
          Support.check_markers ~message rule ~source ~cmt);
    ]
