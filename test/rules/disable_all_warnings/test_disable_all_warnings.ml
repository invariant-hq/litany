(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Disable_all_warnings.rule
let source = "fixtures/fix_daw.ml"
let cmt = "fixtures/.fix_daw.objs/byte/fix_daw.cmt"

let () =
  Windtrap.run "disable-all-warnings"
    [
      test "declares its one metadata record" (fun () ->
          equal string "disable-all-warnings" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          equal string "1.0" (Rule.since rule));
      test "fires exactly on standalone disable-everything payloads" (fun () ->
          Support.check_markers rule
            ~message:"attribute disables all compiler warnings" ~source ~cmt);
    ]
