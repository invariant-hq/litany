(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Suspicious_swallowed_cancellation.rule
let source = "fixtures/fix_ssc.ml"
let cmt = "fixtures/.fix_ssc.objs/byte/fix_ssc.cmt"
let read_file path = In_channel.with_open_bin path In_channel.input_all

let () =
  Windtrap.run "suspicious-swallowed-cancellation"
    [
      test "declares its one metadata record" (fun () ->
          equal string "suspicious-swallowed-cancellation" (Rule.name rule);
          is_true ~msg:"group is Suspicious" (Rule.group rule = Rule.Suspicious);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked swallowing handlers" (fun () ->
          Support.check_markers rule
            ~message:
              "this handler converts Eio cancellation into a value; re-raise \
               Eio.Cancel.Cancelled first"
            ~source ~cmt);
      test "plain arms carry an Unsafe fix; inline arms ship none" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let fixes =
            List.map
              (fun (_, f) -> Litany.Finding.fix f)
              (Litany.Engine.Report.findings rep)
          in
          (* Report order is source order: p1 (fixed), p2 (inline), p3
             (fixed), p4 (inline), p5 (fixed). *)
          equal (list bool)
            [ true; false; true; false; true ]
            (List.map Option.is_some fixes);
          List.iter
            (fun fix ->
              is_true ~msg:"every fix is Unsafe"
                (Litany.Fix.applicability fix = Litany.Fix.Unsafe))
            (List.filter_map Fun.id fixes));
      test "unsafe application round-trips to its compiled golden" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          let plan =
            Litany.Apply.plan ~unsafe:true
              (List.filter_map
                 (fun (rule, f) ->
                   Option.map
                     (fun fix -> { Litany.Apply.rule; fix })
                     (Litany.Finding.fix f))
                 (Litany.Engine.Report.findings rep))
          in
          equal ~msg:"conflicting fixes" int 0
            (List.length (Litany.Apply.conflicting plan));
          equal ~msg:"excluded fixes" int 0
            (List.length (Litany.Apply.excluded plan));
          equal ~msg:"unsafe-fixed bytes vs the committed golden" string
            (read_file "fixtures/fix_ssc.unsafe.fixed.ml")
            (Litany.Apply.patch (read_file source)
               (List.concat_map
                  (fun (c : Litany.Apply.candidate) -> Litany.Fix.edits c.fix)
                  (Litany.Apply.selected plan))));
    ]
