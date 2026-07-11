(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_sequence_ignored_value.rule
let source = "fixtures/fix_ssiv.ml"
let cmt = "fixtures/.fix_ssiv.objs/byte/fix_ssiv.cmt"

let message name =
  "the discarded value is the entire point of " ^ name
  ^ " — the compiler cannot warn here (the type is polymorphic); bind or use \
     the result"

let () =
  Windtrap.run "suspicious-sequence-ignored-value"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-sequence-ignored-value" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked silent discards" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its callee" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            (List.map message
               [
                 "List.hd";
                 "Option.get";
                 "Result.get_ok";
                 "Result.get_error";
                 "fst";
                 "snd";
                 "List.nth";
                 "List.assoc";
                 "List.assq";
                 "List.find";
                 "Hashtbl.find";
               ])
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
