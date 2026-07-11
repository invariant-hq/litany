(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Redundant_conversion_roundtrip.rule
let source = "fixtures/fix_rcr.ml"
let cmt = "fixtures/.fix_rcr.objs/byte/fix_rcr.cmt"

let () =
  Windtrap.run "redundant-conversion-roundtrip"
    [
      test "declares its one metadata record" (fun () ->
          equal string "redundant-conversion-roundtrip" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked roundtrips" (fun () ->
          (* Messages name each pair and its replacement, so the marker
             check asserts lines, not one shared message. *)
          Support.check_markers rule ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_rcr.fixed.ml");
    ]
