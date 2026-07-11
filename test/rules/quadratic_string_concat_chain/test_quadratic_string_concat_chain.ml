(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Quadratic_string_concat_chain.rule
let source = "fixtures/fix_qscc.ml"
let cmt = "fixtures/.fix_qscc.objs/byte/fix_qscc.cmt"
let nested_source = "fixtures/fix_qscc_nested.ml"
let nested_cmt = "fixtures/.fix_qscc_nested.objs/byte/fix_qscc_nested.cmt"

let config_src n =
  Printf.sprintf "(rule quadratic-string-concat-chain\n (max-segments %d))" n

(* The option payload as the driver hands it over: parsed from real config
   text, positions included. *)
let options_of src =
  match Litany.Config_file.parse src with
  | Ok c ->
      Litany.Config_file.Rule_options.options
        (List.hd (Litany.Config_file.rules c))
  | Error e -> failwith (Litany.Config_file.Error.to_string e)

let configured n =
  match Litany.Rule.configure rule (options_of (config_src n)) with
  | Ok r -> r
  | Error e -> failwith e.Litany.Rule.Options.message

let () =
  Windtrap.run "quadratic-string-concat-chain"
    [
      test "declares its one metadata record" (fun () ->
          equal string "quadratic-string-concat-chain" (Rule.name rule);
          is_true ~msg:"group is Pedantic" (Rule.group rule = Rule.Pedantic);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "fires exactly on the marked chains" (fun () ->
          Support.check_markers rule
            ~message:"chained (^) recopies later segments; use String.concat"
            ~source ~cmt);
      test "reports a longer chain once, at its innermost matching node"
        (fun () ->
          (* Containment: a four-segment chain holds two matching
             nodes; only the innermost — rightmost operand simple —
             reports, so one maximal chain is one finding. *)
          let rep = Support.report rule ~source:nested_source ~cmt:nested_cmt in
          equal ~msg:"rule failures" int 0
            (List.length (Litany.Engine.Report.failures rep));
          equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep);
          equal ~msg:"one finding per maximal chain" int 1
            (List.length (Litany.Engine.Report.findings rep));
          Support.check_markers rule
            ~message:"chained (^) recopies later segments; use String.concat"
            ~source:nested_source ~cmt:nested_cmt);
      (* The per-rule option schema (M6): payloads come from a real parsed
         config so the positions the errors carry are the file's. *)
      test "max-segments reconfigures the threshold" (fun () ->
          let n_findings r =
            List.length
              (Litany.Engine.Report.findings
                 (Support.report r ~source:nested_source ~cmt:nested_cmt))
          in
          (* The fixture's chain has four segments: tolerated at threshold
             4, reported at 3 (and at the default 2, above). *)
          equal ~msg:"threshold 4 tolerates four segments" int 0
            (n_findings (configured 4));
          equal ~msg:"threshold 3 reports four segments" int 1
            (n_findings (configured 3));
          (* The reconfigured rule carries the schema: configuring again
             works and the last threshold wins. *)
          match Rule.configure (configured 4) (options_of (config_src 3)) with
          | Ok r -> equal ~msg:"reconfigured twice" int 1 (n_findings r)
          | Error _ -> fail "second configure refused");
      test "option schema refuses bad payloads with positions" (fun () ->
          let refuse src =
            match Rule.configure rule (options_of src) with
            | Ok _ -> fail ("accepted: " ^ src)
            | Error e -> e
          in
          let e =
            refuse "(rule quadratic-string-concat-chain (mxa-segments 4))"
          in
          equal ~msg:"unknown key names itself and suggests" string
            "unknown option \"mxa-segments\" (did you mean \"max-segments\"?)"
            e.Rule.Options.message;
          is_true ~msg:"positioned at the key" (e.Rule.Options.col > 1);
          let e =
            refuse "(rule quadratic-string-concat-chain (max-segments x))"
          in
          equal string "option \"max-segments\" wants an integer, not \"x\""
            e.Rule.Options.message;
          let e =
            refuse "(rule quadratic-string-concat-chain (max-segments 1))"
          in
          equal string "option \"max-segments\" wants an integer >= 2"
            e.Rule.Options.message;
          (* A rule with no schema refuses any payload. *)
          match
            Rule.configure Litany_rules.Needless_list_length.rule
              (options_of "(rule needless-list-length (max-segments 4))")
          with
          | Ok _ -> fail "optionless rule accepted options"
          | Error e ->
              equal string "rule \"needless-list-length\" takes no options"
                e.Rule.Options.message);
    ]
