(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_ambiguous_constructors.rule
let source = "fixtures/fix_sac.ml"
let cmt = "fixtures/.fix_sac.objs/byte/fix_sac.cmt"

let message name =
  Printf.sprintf
    "constructor %s shadows the standard %s: unannotated uses below this point \
     resolve here"
    name name

let () =
  Windtrap.run "suspicious-ambiguous-constructors"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-ambiguous-constructors" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked shadowing constructors" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names the shadowed constructor" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              message "Error";
              message "Ok";
              message "Some";
              message "None";
              message "Some";
              message "::";
              message "[]";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
