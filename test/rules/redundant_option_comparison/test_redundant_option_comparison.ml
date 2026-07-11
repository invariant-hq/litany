(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_option_comparison.rule
let source = "fixtures/fix_roc.ml"
let cmt = "fixtures/.fix_roc.objs/byte/fix_roc.cmt"

let () =
  Windtrap.run "redundant-option-comparison"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-option-comparison" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked None comparisons" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its predicate; chains count their members"
        (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_some";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_some";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_some";
              "3 comparisons with None are longhand for Option predicates";
              "2 comparisons with None are longhand for Option predicates";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_none";
              "2 comparisons with None are longhand for Option predicates";
              "comparison with None is longhand for Option.is_none";
              "comparison with None is longhand for Option.is_none";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_roc.fixed.ml");
    ]
