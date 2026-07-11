(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_boolean_comparison.rule
let source = "fixtures/fix_rbc.ml"
let cmt = "fixtures/.fix_rbc.objs/byte/fix_rbc.cmt"

let () =
  Windtrap.run "redundant-boolean-comparison"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-boolean-comparison" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked constant comparisons" (fun () ->
          Support.check_markers rule
            ~message:"comparison with a boolean constant is redundant" ~source
            ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rbc.fixed.ml");
      test "the negate cell round-trips to the compiled unsafe golden"
        (fun () ->
          Support.check_fixed ~unsafe:true rule ~source ~cmt
            ~golden:"fixtures/fix_rbc.unsafe.ml");
    ]
