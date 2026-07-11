(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_option_value.rule
let source = "fixtures/fix_mov.ml"
let cmt = "fixtures/.fix_mov.objs/byte/fix_mov.cmt"

let () =
  Windtrap.run "manual-option-value"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-option-value" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked trivial-default matches" (fun () ->
          Support.check_markers rule
            ~message:
              "a trivial-default option match is Option.value in longhand"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mov.fixed.ml");
    ]
