(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Eta_reducible_forwarding.rule
let source = "fixtures/fix_erf.ml"
let cmt = "fixtures/.fix_erf.objs/byte/fix_erf.cmt"

let () =
  Windtrap.run "eta-reducible-forwarding"
    [
      test "declares its one metadata record" (fun () ->
          equal string "eta-reducible-forwarding" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked forwarding bindings" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "messages name the forwarding target" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let prefix = "this binding only forwards its arguments; it is " in
          let messages =
            List.map
              (fun (_, f) -> Litany.Finding.message f)
              (Litany.Engine.Report.findings rep)
          in
          List.iter
            (fun m ->
              is_true ~msg:"message carries the eta-reduction claim"
                (String.starts_with ~prefix m))
            messages;
          is_true ~msg:"the operator forward names Stdlib.+"
            (List.exists
               (fun m -> m = prefix ^ "eta-reducible to Stdlib.+")
               messages));
    ]
