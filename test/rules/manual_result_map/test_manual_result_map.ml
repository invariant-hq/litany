(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_result_map.rule
let source = "fixtures/fix_mrm.ml"
let cmt = "fixtures/.fix_mrm.objs/byte/fix_mrm.cmt"

let map_message =
  "this match transforms the payload and rebuilds the error; use Result.map"

let map_error_message =
  "this match transforms the error and rebuilds the payload; use \
   Result.map_error"

let identity_message =
  "this match rebuilds the result unchanged; it is the scrutinee itself"

let () =
  Windtrap.run "manual-result-map"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-result-map" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual result maps" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its form" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              map_message;
              map_message;
              map_error_message;
              identity_message;
              map_error_message;
              map_error_message;
              map_message;
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mrm.fixed.ml");
    ]
