(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_option_roundtrip.rule
let source = "fixtures/fix_ror.ml"
let cmt = "fixtures/.fix_ror.objs/byte/fix_ror.cmt"

let () =
  Windtrap.run "redundant-option-roundtrip"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-option-roundtrip" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked roundtrips" (fun () ->
          Support.check_markers rule
            ~message:
              "option-to-list conversion followed by List.nth_opt is redundant"
            ~source ~cmt);
    ]
