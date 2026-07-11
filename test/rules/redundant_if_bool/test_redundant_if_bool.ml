(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_if_bool.rule
let source = "fixtures/fix_rib.ml"
let cmt = "fixtures/.fix_rib.objs/byte/fix_rib.cmt"

let () =
  Windtrap.run "redundant-if-bool"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-if-bool" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked two-literal ifs" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its rewrite" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              "if c then true else false is longhand for c";
              "if c then false else true is longhand for not c";
              "if c then true else false is longhand for c";
              "if c then false else true is longhand for not c";
              "if c then false else true is longhand for not c";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rib.fixed.ml");
      test "the negation cell round-trips to the compiled unsafe golden"
        (fun () ->
          Support.check_fixed ~unsafe:true rule ~source ~cmt
            ~golden:"fixtures/fix_rib.unsafe.ml");
    ]
