(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Quadratic_string_concat_fold.rule
let source = "fixtures/fix_qscf.ml"
let cmt = "fixtures/.fix_qscf.objs/byte/fix_qscf.cmt"

let () =
  Windtrap.run "quadratic-string-concat-fold"
    [
      test "declares its one metadata record" (fun () ->
          equal string "quadratic-string-concat-fold" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked folds over (^)" (fun () ->
          Support.check_markers rule
            ~message:
              "folding (^) copies the accumulator per element; use \
               String.concat"
            ~source ~cmt);
    ]
