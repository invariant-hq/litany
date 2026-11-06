(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Untyped_wildcard_binding.rule
let source = "fixtures/fix_uwb.ml"
let cmt = "fixtures/.fix_uwb.objs/byte/fix_uwb.cmt"

let () =
  Windtrap.run "untyped-wildcard-binding"
    [
      test "declares its one metadata record" (fun () ->
          equal string "untyped-wildcard-binding" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.1" (Rule.since rule));
      test "fires exactly on the marked discards" (fun () ->
          Support.check_markers rule ~source ~cmt);
    ]
