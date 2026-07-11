(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_polymorphic_compare_on_opaque.rule
let source = "fixtures/fix_spco.ml"
let cmt = "fixtures/.fix_spco.objs/byte/fix_spco.cmt"

let () =
  Windtrap.run "suspicious-polymorphic-compare-on-opaque"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-polymorphic-compare-on-opaque"
            (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked opaque comparisons" (fun () ->
          Support.check_markers rule
            ~message:
              "polymorphic comparison reads an opaque representation, not its \
               contents"
            ~source ~cmt);
    ]
