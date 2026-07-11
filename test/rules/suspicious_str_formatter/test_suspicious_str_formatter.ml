(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_str_formatter.rule
let source = "fixtures/fix_ssf.ml"
let cmt = "fixtures/.fix_ssf.objs/byte/fix_ssf.cmt"

let () =
  Windtrap.run "suspicious-str-formatter"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-str-formatter" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked global-formatter references" (fun () ->
          Support.check_markers rule
            ~message:
              "Format.str_formatter is one process-global buffer; use \
               Format.asprintf"
            ~kind:Litany.Roster.Library ~source ~cmt);
      test "degrades to silence without kind metadata" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal ~msg:"no findings without kind" int 0
            (List.length (Litany.Engine.Report.findings rep)));
      test "executables are out of scope" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Executable ~source ~cmt
          in
          equal ~msg:"no findings for executables" int 0
            (List.length (Litany.Engine.Report.findings rep)));
    ]
