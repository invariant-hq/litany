(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Unsafe_obj_magic.rule
let source = "fixtures/fix_uom.ml"
let cmt = "fixtures/.fix_uom.objs/byte/fix_uom.cmt"

let () =
  Windtrap.run "unsafe-obj-magic"
    [
      test "declares its one metadata record" (fun () ->
          equal string "unsafe-obj-magic" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked Obj.magic identifiers" (fun () ->
          Support.check_markers rule
            ~message:"Obj.magic bypasses the type system" ~source ~cmt);
    ]
