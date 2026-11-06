(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Untyped_ignore.rule
let source = "fixtures/fix_ui.ml"
let cmt = "fixtures/.fix_ui.objs/byte/fix_ui.cmt"

let () =
  exit
  @@ Windtrap.run "untyped-ignore"
       [
         test "declares its one metadata record" (fun () ->
             equal string "untyped-ignore" (Rule.name rule);
             is_true ~msg:"group is Restriction"
               (Rule.group rule = Rule.Restriction);
             is_true ~msg:"nursery"
               (Rule.stability rule = Rule.Stability.Nursery);
             is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
             is_true ~msg:"local rule" (not (Rule.is_project rule));
             equal string "1.1" (Rule.since rule));
         test "fires exactly on the marked discards" (fun () ->
             Support.check_markers rule ~source ~cmt);
       ]
