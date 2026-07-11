(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_list_map_before_concat.rule
let source = "fixtures/fix_mbc.ml"
let cmt = "fixtures/.fix_mbc.objs/byte/fix_mbc.cmt"

let () =
  Windtrap.run "needless-list-map-before-concat"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-list-map-before-concat" (Rule.name rule);
          is_true ~msg:"group is Perf" (Rule.group rule = Rule.Perf);
          is_true ~msg:"stable — graduated on reviewed field evidence"
            (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked map-before-concat shapes" (fun () ->
          Support.check_markers rule
            ~message:
              "List.map immediately before list concatenation creates an \
               intermediate list"
            ~source ~cmt);
    ]
