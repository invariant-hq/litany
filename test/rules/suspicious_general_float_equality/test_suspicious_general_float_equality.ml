(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_general_float_equality.rule
let source = "fixtures/fix_sgfe.ml"
let cmt = "fixtures/.fix_sgfe.objs/byte/fix_sgfe.cmt"

let message =
  "float equality is bit-exact — compare within a margin, or write Float.equal \
   (or annotate) if exact comparison is intended"

let () =
  Windtrap.run "suspicious-general-float-equality"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-general-float-equality" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked float comparisons" (fun () ->
          Support.check_markers ~message rule ~source ~cmt);
    ]
