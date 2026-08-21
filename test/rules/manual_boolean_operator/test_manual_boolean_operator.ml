(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_boolean_operator.rule
let source = "fixtures/fix_mbo.ml"
let cmt = "fixtures/.fix_mbo.objs/byte/fix_mbo.cmt"

let () =
  Windtrap.run "manual-boolean-operator"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-boolean-operator" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked one-literal ifs" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its rewrite" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              "if c then true else e is longhand for c || e";
              "if c then e else false is longhand for c && e";
              "if c then e else true is longhand for not c || e";
              "if c then false else e is longhand for not c && e";
              "if c then true else e is longhand for c || e";
              "if c then true else e is longhand for c || e";
              "if c then false else e is longhand for not c && e";
              "if c then true else e is longhand for c || e";
              "if c then true else e is longhand for c || e";
              "if c then true else e is longhand for c || e";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "every fix is unsafe: the golden equals the fixture byte for byte"
        (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mbo.fixed.ml");
      test "the operator rewrites round-trip to the compiled unsafe golden"
        (fun () ->
          Support.check_fixed ~unsafe:true rule ~source ~cmt
            ~golden:"fixtures/fix_mbo.unsafe.ml");
    ]
