(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_list_map.rule
let source = "fixtures/fix_mlm.ml"
let cmt = "fixtures/.fix_mlm.objs/byte/fix_mlm.cmt"

let () =
  Windtrap.run "manual-list-map"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-list-map" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual maps" (fun () ->
          Support.check_markers rule
            ~message:"manual list recursion hand-rolls List.map" ~source ~cmt);
    ]
