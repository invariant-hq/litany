(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Manual_format_quoting.rule
let source = "fixtures/fix_mfq.ml"
let cmt = "fixtures/.fix_mfq.objs/byte/fix_mfq.cmt"
let read path = In_channel.with_open_bin path In_channel.input_all

(* [Support.check_fixed] plans at the Safe level; this rule's fix is
   deliberately Unsafe (%S escapes where hand-quoting does not), so the
   round-trip here plans with [~unsafe:true] — the [--fix --unsafe]
   level — against the same compiled golden discipline. *)
let check_fixed_unsafe ~golden =
  let rep = Support.report rule ~source ~cmt in
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep);
  let findings =
    Litany.Engine.Report.findings rep
    @ List.map (fun (r, f, _) -> (r, f)) (Litany.Engine.Report.expected rep)
  in
  let candidates =
    List.filter_map
      (fun (rule, f) ->
        Option.map
          (fun fix -> { Litany.Apply.rule; fix })
          (Litany.Finding.fix f))
      findings
  in
  List.iter
    (fun (c : Litany.Apply.candidate) ->
      is_true ~msg:"every fix is Unsafe"
        (Litany.Fix.applicability c.fix = Litany.Fix.Unsafe))
    candidates;
  let plan = Litany.Apply.plan ~unsafe:true candidates in
  equal ~msg:"conflicting fixes (a fixture defect: split the fixture)" int 0
    (List.length (Litany.Apply.conflicting plan));
  let fixed =
    Litany.Apply.patch (read source)
      (List.concat_map
         (fun (c : Litany.Apply.candidate) -> Litany.Fix.edits c.fix)
         (Litany.Apply.selected plan))
  in
  equal ~msg:"fixed bytes vs the committed golden" string (read golden) fixed

let () =
  Windtrap.run "manual-format-quoting"
    [
      test "declares its one metadata record" (fun () ->
          equal string "manual-format-quoting" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked hand-quoted literals" (fun () ->
          Support.check_markers rule
            ~message:"hand-quoted %s re-implements %S without its escaping"
            ~source ~cmt);
      test "unsafe fixes round-trip to the compiled golden" (fun () ->
          check_fixed_unsafe ~golden:"fixtures/fix_mfq.fixed.ml");
    ]
