(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_transposable_arguments.rule

let message =
  "three adjacent same-typed unlabeled parameters invite silent transposition; \
   label them"

let source = "fixtures/fix_sta.ml"
let cmt = "fixtures/.fix_sta.objs/byte/fix_sta.cmt"
let pub_source = "fixtures/fix_sta_pub.ml"
let pub_cmt = "fixtures/.fix_sta_pub.objs/byte/fix_sta_pub.cmt"
let pub_cmti = "fixtures/.fix_sta_pub.objs/byte/fix_sta_pub.cmti"

let () =
  Windtrap.run "suspicious-transposable-arguments"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-transposable-arguments" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked derived-export bindings" (fun () ->
          Support.check_markers rule ~message ~kind:Litany.Roster.Library
            ~source ~cmt);
      test "the interface decides the mli-backed export surface" (fun () ->
          Support.check_markers rule ~message ~cmti:pub_cmti
            ~kind:Litany.Roster.Library ~source:pub_source ~cmt:pub_cmt);
      test "degrades to silence without kind metadata" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal ~msg:"no findings without kind" int 0
            (List.length (Litany.Engine.Report.findings rep)));
      test "executables are out of scope" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Executable ~source ~cmt
          in
          equal ~msg:"no findings for executables" int 0
            (List.length (Litany.Engine.Report.findings rep)));
    ]
