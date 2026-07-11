(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_list_fold.rule
let source = "fixtures/fix_mlf.ml"
let cmt = "fixtures/.fix_mlf.objs/byte/fix_mlf.cmt"

let () =
  Windtrap.run "manual-list-fold"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-list-fold" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual folds" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its replacement" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              "manual list recursion re-implements List.fold_left";
              "manual list recursion re-implements List.fold_left";
              "manual list recursion re-implements List.fold_right";
              "manual list recursion re-implements List.fold_left";
              "manual list recursion re-implements List.fold_right";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
