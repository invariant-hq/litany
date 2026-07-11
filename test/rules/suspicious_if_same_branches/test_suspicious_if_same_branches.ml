(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_if_same_branches.rule

let message =
  "the two branches are identical — either the condition is unnecessary or one \
   branch was meant to differ"

let () =
  Windtrap.run "suspicious-if-same-branches"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-if-same-branches" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked identical-branch ifs" (fun () ->
          Support.check_markers ~message rule ~source:"fixtures/fix_sisb.ml"
            ~cmt:"fixtures/.fix_sisb.objs/byte/fix_sisb.cmt");
      test "normalization equates whitespace-only differences" (fun () ->
          Support.check_markers ~message rule ~source:"fixtures/ws_sisb.ml"
            ~cmt:"fixtures/.ws_sisb.objs/byte/ws_sisb.cmt");
    ]
