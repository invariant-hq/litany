(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_mutually_recursive_types.rule
let source = "fixtures/fix_nmrt.ml"
let cmt = "fixtures/.fix_nmrt.objs/byte/fix_nmrt.cmt"

let message name =
  Printf.sprintf
    "%s is declared with 'and' but is not mutually recursive with its group — \
     declare it as its own type"
    name

let () =
  Windtrap.run "needless-mutually-recursive-types"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-mutually-recursive-types" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked extractable declarations" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names the extractable declaration" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            (List.map message
               [
                 "t1";
                 "t2";
                 "t3";
                 "q3";
                 "g1";
                 "g2";
                 "g3";
                 "g4";
                 "g7";
                 "g8";
                 "g9";
                 "na";
                 "nb";
                 "sc";
               ])
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
