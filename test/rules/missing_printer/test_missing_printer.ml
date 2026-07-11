(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Missing_printer.rule

let check_clean rep =
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep)

let finding_lines rep =
  List.map
    (fun (_, f) -> (Litany.Finding.loc f).Location.loc_start.Lexing.pos_lnum)
    (Litany.Engine.Report.findings rep)

let () =
  Windtrap.run "missing-printer"
    [
      test "declares its one metadata record" (fun () ->
          equal string "missing-printer" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked comparable abstract types" (fun () ->
          Support.check_markers rule
            ~cmti:"fixtures/.fix_mpr.objs/byte/fix_mpr.cmti"
            ~message:
              "this abstract type is comparable in its interface but has no \
               printer"
            ~source:"fixtures/fix_mpr.ml"
            ~cmt:"fixtures/.fix_mpr.objs/byte/fix_mpr.cmt");
      test "the negative interface is silent" (fun () ->
          let rep =
            Support.report rule
              ~cmti:"fixtures/.fix_mpr_neg.objs/byte/fix_mpr_neg.cmti"
              ~source:"fixtures/fix_mpr_neg.ml"
              ~cmt:"fixtures/.fix_mpr_neg.objs/byte/fix_mpr_neg.cmt"
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a unit without an interface is silent" (fun () ->
          let rep =
            Support.report rule ~source:"fixtures/fix_mpr.ml"
              ~cmt:"fixtures/.fix_mpr.objs/byte/fix_mpr.cmt"
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
    ]
