(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_unused_module_binding.rule
let source = "fixtures/fix_sumb.ml"
let cmt = "fixtures/.fix_sumb.objs/byte/fix_sumb.cmt"
let cmti = "fixtures/.fix_sumb.objs/byte/fix_sumb.cmti"
let nomli_source = "fixtures/fix_sumb_nomli.ml"
let nomli_cmt = "fixtures/.fix_sumb_nomli.objs/byte/fix_sumb_nomli.cmt"

let toplevel_message =
  "this module is never used in the unit and its interface does not export it"

let local_message = "this local module is never used"

let () =
  Windtrap.run "suspicious-unused-module-binding"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-unused-module-binding" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked unused bindings" (fun () ->
          Support.check_markers rule ~cmti ~source ~cmt);
      test "messages split by binding level" (fun () ->
          let rep = Support.report rule ~cmti ~source ~cmt in
          equal (list string)
            [ toplevel_message; toplevel_message; local_message ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "a unit without an interface exports everything and is silent"
        (fun () ->
          Support.check_markers rule ~source:nomli_source ~cmt:nomli_cmt);
    ]
