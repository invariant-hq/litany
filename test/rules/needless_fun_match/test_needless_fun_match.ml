(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_fun_match.rule
let source = "fixtures/fix_nfm.ml"
let cmt = "fixtures/.fix_nfm.objs/byte/fix_nfm.cmt"

let () =
  Windtrap.run "needless-fun-match"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-fun-match" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked fun-match shapes" (fun () ->
          Support.check_markers rule
            ~message:
              "match on an otherwise unused final parameter is longhand for \
               function"
            ~source ~cmt);
    ]
