(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Open_of_ordinary_module.rule
let source = "fixtures/fix_oom_cases.ml"
let cmt = "fixtures/.fix_oom.objs/byte/fix_oom__Fix_oom_cases.cmt"

let () =
  Windtrap.run "open-of-ordinary-module"
    [
      test "declares its one metadata record" (fun () ->
          equal string "open-of-ordinary-module" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.1" (Rule.since rule));
      test "fires exactly on the marked opens" (fun () ->
          Support.check_markers rule ~source ~cmt);
    ]
