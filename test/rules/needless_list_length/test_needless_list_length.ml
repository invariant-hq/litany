(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_list_length.rule
let source = "fixtures/fix_nll.ml"
let cmt = "fixtures/.fix_nll.objs/byte/fix_nll.cmt"

let () =
  Windtrap.run "needless-list-length"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-list-length" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked emptiness comparisons" (fun () ->
          Support.check_markers rule
            ~message:
              "comparison through List.length is a needless emptiness test"
            ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_nll.fixed.ml");
    ]
