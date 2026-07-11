(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_list_forall.rule
let source = "fixtures/fix_mlfa.ml"
let cmt = "fixtures/.fix_mlfa.objs/byte/fix_mlfa.cmt"

let () =
  Windtrap.run "manual-list-forall"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-list-forall" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual for_alls" (fun () ->
          Support.check_markers rule
            ~message:"manual list recursion re-implements List.for_all" ~source
            ~cmt);
    ]
