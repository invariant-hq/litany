(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_file_exists_race.rule
let source = "fixtures/fix_sfer.ml"
let cmt = "fixtures/.fix_sfer.objs/byte/fix_sfer.cmt"

let () =
  Windtrap.run "suspicious-file-exists-race"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-file-exists-race" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked exists-guarded operations" (fun () ->
          Support.check_markers rule
            ~message:
              "the exists check races with the guarded operation; perform it \
               and handle the exception"
            ~source ~cmt);
    ]
