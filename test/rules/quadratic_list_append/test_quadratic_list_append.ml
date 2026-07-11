(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Quadratic_list_append.rule
let source = "fixtures/fix_qla.ml"
let cmt = "fixtures/.fix_qla.objs/byte/fix_qla.cmt"

let () =
  Windtrap.run "quadratic-list-append"
    [
      test "declares its one metadata record" (fun () ->
          equal string "quadratic-list-append" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked quadratic folds" (fun () ->
          Support.check_markers rule
            ~message:
              "(@) copies its left operand, making this fold quadratic; use \
               List.concat, List.concat_map, or :: with List.rev"
            ~source ~cmt);
    ]
