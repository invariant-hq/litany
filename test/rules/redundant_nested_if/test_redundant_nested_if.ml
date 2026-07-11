(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_nested_if.rule
let source = "fixtures/fix_rni.ml"
let cmt = "fixtures/.fix_rni.objs/byte/fix_rni.cmt"

let () =
  Windtrap.run "redundant-nested-if"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-nested-if" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked nested ifs" (fun () ->
          Support.check_markers rule
            ~message:
              "if c1 then if c2 then e is longhand for if c1 && c2 then e"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rni.fixed.ml");
    ]
