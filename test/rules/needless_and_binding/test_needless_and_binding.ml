(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_and_binding.rule
let source = "fixtures/fix_nab.ml"
let cmt = "fixtures/.fix_nab.objs/byte/fix_nab.cmt"

let self_message name =
  Printf.sprintf
    "%s is recursive but not mutually recursive with its group — extract it as \
     its own let rec"
    name

let inert_message name =
  Printf.sprintf
    "%s references no binding of its group — extract it as a plain let" name

let () =
  Windtrap.run "needless-and-binding"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-and-binding" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked wasted chain links" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message carries the binding's classification" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              inert_message "double";
              self_message "fib";
              inert_message "memo";
              self_message "selfa";
              self_message "selfb";
              self_message "go_around";
              inert_message "go_label";
              inert_message "ida";
              inert_message "idb";
              inert_message "pea";
              inert_message "qea";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
