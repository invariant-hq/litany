(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Invalid_nan_comparison.rule
let source = "fixtures/fix_inc.ml"
let cmt = "fixtures/.fix_inc.objs/byte/fix_inc.cmt"

let () =
  Windtrap.run "invalid-nan-comparison"
    [
      test "declares its one metadata record" (fun () ->
          equal string "invalid-nan-comparison" (Rule.name rule);
          is_true ~msg:"group is Correctness"
            (Rule.group rule = Rule.Correctness);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked nan comparisons" (fun () ->
          Support.check_markers rule
            ~message:
              "nan is unordered, so this comparison is constant; use \
               Float.is_nan"
            ~source ~cmt);
    ]
