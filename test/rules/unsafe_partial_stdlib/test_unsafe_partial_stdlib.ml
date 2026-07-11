(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Unsafe_partial_stdlib.rule
let source = "fixtures/fix_ups.ml"
let cmt = "fixtures/.fix_ups.objs/byte/fix_ups.cmt"

let () =
  Windtrap.run "unsafe-partial-stdlib"
    [
      test "declares its one metadata record" (fun () ->
          equal string "unsafe-partial-stdlib" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked partial references" (fun () ->
          (* Messages name each eliminator's own remedy, so the marker
             check asserts lines, not one shared message. *)
          Support.check_markers rule ~source ~cmt);
    ]
