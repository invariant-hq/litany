(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_variant_arity_tuple.rule
let source = "fixtures/fix_svat.ml"
let cmt = "fixtures/.fix_svat.objs/byte/fix_svat.cmt"

let message name =
  Printf.sprintf
    "%s of (a * b) declares one boxed tuple field — %s of a * b declares two \
     inline fields; name the tuple type if the boxing is deliberate"
    name name

let () =
  Windtrap.run "suspicious-variant-arity-tuple"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-variant-arity-tuple" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked boxed tuple arguments" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names the boxed constructor" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            (List.map message [ "Pair"; "B"; "Pt"; "Node" ])
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
    ]
