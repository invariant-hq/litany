(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_option_map.rule
let source = "fixtures/fix_mom.ml"
let cmt = "fixtures/.fix_mom.objs/byte/fix_mom.cmt"

let map_message =
  "this match unwraps, transforms, and rewraps the option; use Option.map"

let identity_message =
  "this match rebuilds the option unchanged; it is the scrutinee itself"

let () =
  Windtrap.run "manual-option-map"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-option-map" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked manual maps" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message states its rewrite" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              map_message;
              map_message;
              map_message;
              identity_message;
              map_message;
              map_message;
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mom.fixed.ml");
    ]
