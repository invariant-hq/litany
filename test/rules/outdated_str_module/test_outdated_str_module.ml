(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Outdated_str_module.rule
let source = "fixtures/fix_osm.ml"
let cmt = "fixtures/.fix_osm.objs/byte/fix_osm.cmt"
let plain = "Str answers matches through global state; use Re"

let () =
  Windtrap.run "outdated-str-module"
    [
      test "declares its one metadata record" (fun () ->
          equal string "outdated-str-module" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable — graduated on reviewed field evidence"
            (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked cluster anchors" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "clusters count their references; singles keep the plain message"
        (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              plain;
              plain;
              plain;
              "Str.quote referenced 2 times in this unit; " ^ plain;
              "Str.global_replace referenced 3 times in this unit; " ^ plain;
              "Str.split referenced 2 times in this unit; " ^ plain;
              "Str.bounded_split referenced 2 times in this unit; " ^ plain;
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
