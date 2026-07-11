(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Invalid_hashtable_key.rule
let source = "fixtures/fix_ihk.ml"
let cmt = "fixtures/.fix_ihk.objs/byte/fix_ihk.cmt"

let () =
  Windtrap.run "invalid-hashtable-key"
    [
      test "declares its one metadata record" (fun () ->
          equal string "invalid-hashtable-key" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked functional subjects" (fun () ->
          Support.check_markers rule
            ~message:
              "Hashtbl's polymorphic hash is unreliable on functional values: \
               nondeterministic per run, and lookups miss or raise"
            ~source ~cmt);
    ]
