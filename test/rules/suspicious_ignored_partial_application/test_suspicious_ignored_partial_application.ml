(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_ignored_partial_application.rule
let source = "fixtures/fix_sipa.ml"
let cmt = "fixtures/.fix_sipa.objs/byte/fix_sipa.cmt"

let () =
  Windtrap.run "suspicious-ignored-partial-application"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-ignored-partial-application" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked ignored functions" (fun () ->
          Support.check_markers rule
            ~message:
              "ignored value is still a function; supply the missing arguments \
               or bind it as let (_ : _ -> _)"
            ~source ~cmt);
    ]
