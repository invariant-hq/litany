(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_list_filter_map.rule
let source = "fixtures/fix_mlfm.ml"
let cmt = "fixtures/.fix_mlfm.objs/byte/fix_mlfm.cmt"

let () =
  Windtrap.run "manual-list-filter-map"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-list-filter-map" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked cons-or-skip recursions" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its replacement" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              "manual list recursion re-implements List.filter";
              "manual list recursion re-implements List.filter";
              "manual list recursion re-implements List.filter_map";
              "manual list recursion re-implements List.filter_map";
              "manual list recursion re-implements List.filter_map";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
