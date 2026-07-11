(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_identity_function.rule
let source = "fixtures/fix_nif.ml"
let cmt = "fixtures/.fix_nif.objs/byte/fix_nif.cmt"

let () =
  Windtrap.run "needless-identity-function"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-identity-function" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked forwarding wrappers" (fun () ->
          Support.check_markers rule
            ~message:"function only forwards its arguments to another function"
            ~source ~cmt);
    ]
