(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Needless_append_empty.rule
let source = "fixtures/fix_nae.ml"
let cmt = "fixtures/.fix_nae.objs/byte/fix_nae.cmt"
let read_file path = In_channel.with_open_bin path In_channel.input_all

(* Every finding's fix, in report order. *)
let fixes () =
  List.map
    (fun (_, f) ->
      match Litany.Finding.fix f with
      | Some fix -> fix
      | None -> failwith "finding without a fix")
    (Litany.Engine.Report.findings (Support.report rule ~source ~cmt))

let () =
  Windtrap.run "needless-append-empty"
    [
      test "declares its one metadata record" (fun () ->
          equal string "needless-append-empty" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Sometimes"
            (Rule.fix rule = Rule.Sometimes);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked neutral operations" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "each message names its family" (fun () ->
          let list_m = "appending the empty list is redundant" in
          let string_m = "concatenating the empty string is redundant" in
          let rep = Support.report rule ~source ~cmt in
          equal (list string)
            [
              list_m;
              list_m;
              list_m;
              list_m;
              string_m;
              string_m;
              string_m;
              string_m;
              list_m;
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "only the identity-preserving leg is Safe" (fun () ->
          (* p1 `[] @ acc`, p4 `List.append [] t`, and p9 `[] @ []` keep
             physical identity; every other leg removes a copy. *)
          equal (list bool)
            [ true; false; false; true; false; false; false; false; true ]
            (List.map
               (fun fix -> Litany.Fix.applicability fix = Litany.Fix.Safe)
               (fixes ())));
      test "Safe fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_nae.fixed.ml");
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
            (read_file "fixtures/fix_nae.unsafe.fixed.ml")
            (Litany.Apply.patch (read_file source)
               (List.concat_map
                  (fun (c : Litany.Apply.candidate) -> Litany.Fix.edits c.fix)
                  (Litany.Apply.selected plan))));
    ]
