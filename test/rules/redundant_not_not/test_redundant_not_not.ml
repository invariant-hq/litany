(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_not_not.rule
let source = "fixtures/fix_rnn.ml"
let cmt = "fixtures/.fix_rnn.objs/byte/fix_rnn.cmt"
let message = "double negation is redundant"

let () =
  Windtrap.run "redundant-not-not"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-not-not" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked double negations" (fun () ->
          Support.check_markers ~message rule ~source ~cmt);
      test "a quadruple negation fires at every nested pair" (fun () ->
          Support.check_markers ~message rule ~source:"fixtures/quad_rnn.ml"
            ~cmt:"fixtures/.quad_rnn.objs/byte/quad_rnn.cmt");
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rnn.fixed.ml");
    ]
