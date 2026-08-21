(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_eta_lambda.rule
let source = "fixtures/fix_mel.ml"
let cmt = "fixtures/.fix_mel.objs/byte/fix_mel.cmt"

let () =
  Windtrap.run "manual-eta-lambda"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-eta-lambda" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked forwarding lambdas" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names the callee as written" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let prefix = "this function only forwards its parameters; it is " in
          equal (list string)
            (List.map
               (fun c -> prefix ^ c)
               [
                 "parse";
                 "step";
                 "step";
                 "add";
                 "String.length";
                 "List.length";
                 "add";
                 "step";
                 "step";
                 "step";
                 "step";
                 "step";
                 "size";
               ])
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "every finding carries a Safe fix" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          List.iter
            (fun (_, f) ->
              match Litany.Finding.fix f with
              | Some fix ->
                  is_true ~msg:"Safe"
                    (Litany.Fix.applicability fix = Litany.Fix.Safe)
              | None -> fail "finding without a fix")
            (Litany.Engine.Report.findings rep));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mel.fixed.ml");
    ]
