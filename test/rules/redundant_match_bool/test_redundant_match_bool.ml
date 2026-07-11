(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_match_bool.rule
let source = "fixtures/fix_rmb.ml"
let cmt = "fixtures/.fix_rmb.objs/byte/fix_rmb.cmt"

let () =
  Windtrap.run "redundant-match-bool"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-match-bool" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked boolean matches" (fun () ->
          Support.check_markers rule
            ~message:
              "two-case match on a boolean is an if-then-else in longhand"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rmb.fixed.ml");
    ]
