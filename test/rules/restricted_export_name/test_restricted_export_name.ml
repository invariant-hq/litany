(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Restricted_export_name.rule
let mli_source = "fixtures/fix_ren.ml"
let mli_cmt = "fixtures/.fix_ren.objs/byte/fix_ren.cmt"
let mli_cmti = "fixtures/.fix_ren.objs/byte/fix_ren.cmti"
let bare_source = "fixtures/fix_ren_bare.ml"
let bare_cmt = "fixtures/.fix_ren_bare.objs/byte/fix_ren_bare.cmt"

(* Payload constructors: positioned s-expressions as the config parser
   hands them to the schema. Positions are synthetic (1:1) — the cram
   suite pins real positions from a real config file. *)
let atom s = { Litany.Sexp.desc = Litany.Sexp.Atom s; line = 1; col = 1 }
let form xs = { Litany.Sexp.desc = Litany.Sexp.List xs; line = 1; col = 1 }
let forbid_suffix s = form [ atom "forbid-suffix"; atom s ]
let max_underscores n = form [ atom "max-underscores"; atom (string_of_int n) ]

(* The suite's configuration: the two closed options at the values the
   fixtures are written against. *)
let payload = [ forbid_suffix "'"; max_underscores 3 ]

let configured payload =
  match Rule.configure rule payload with
  | Ok r -> r
  | Error e -> failf "schema refused: %s" (Rule.Options.to_string e)

let refused payload =
  match Rule.configure rule payload with
  | Ok _ -> fail "schema accepted; expected a refusal"
  | Error e -> e.Rule.Options.message

let check_clean rep =
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep)

let messages rep =
  List.map
    (fun (_, f) -> Litany.Finding.message f)
    (Litany.Engine.Report.findings rep)

let () =
  Windtrap.run "restricted-export-name"
    [
      test "declares its one metadata record" (fun () ->
          equal string "restricted-export-name" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "unconfigured, the rule is inert" (fun () ->
          let rep =
            Support.report rule ~cmti:mli_cmti ~source:mli_source ~cmt:mli_cmt
          in
          check_clean rep;
          equal ~msg:"no restrictions, no findings" (list string) []
            (messages rep));
      test "mli-backed: fires exactly on the marked exported names" (fun () ->
          Support.check_markers (configured payload) ~cmti:mli_cmti
            ~source:mli_source ~cmt:mli_cmt);
      test "ml-only: the derived signature exports every root name" (fun () ->
          Support.check_markers (configured payload) ~source:bare_source
            ~cmt:bare_cmt);
      test "messages name the condemning option" (fun () ->
          let rep =
            Support.report (configured payload) ~cmti:mli_cmti
              ~source:mli_source ~cmt:mli_cmt
          in
          check_clean rep;
          equal (list string)
            [
              "t' ends with \"'\", forbidden in exported names by \
               (forbid-suffix ')";
              "parse' ends with \"'\", forbidden in exported names by \
               (forbid-suffix ')";
              "a_b_c_d_e carries 4 underscores, over the (max-underscores 3) \
               limit for exported names";
              "refl' ends with \"'\", forbidden in exported names by \
               (forbid-suffix ')";
            ]
            (messages rep));
      test "an empty payload configures the inert rule" (fun () ->
          let rep =
            Support.report (configured []) ~cmti:mli_cmti ~source:mli_source
              ~cmt:mli_cmt
          in
          check_clean rep;
          equal (list string) [] (messages rep));
      test "the reconfigured rule re-attaches the schema" (fun () ->
          let once = configured [ forbid_suffix "'" ] in
          match Rule.configure once [ max_underscores 2 ] with
          | Ok _ -> ()
          | Error e ->
              failf "second configure refused: %s" (Rule.Options.to_string e));
      test "schema refusals are actionable config errors" (fun () ->
          equal ~msg:"empty suffix" string
            "forbid-suffix wants a non-empty suffix"
            (refused [ forbid_suffix "" ]);
          equal ~msg:"duplicate suffix" string {|suffix "'" is forbidden twice|}
            (refused [ forbid_suffix "'"; forbid_suffix "'" ]);
          equal ~msg:"non-integer count" string
            {|max-underscores wants a non-negative count, not "many"|}
            (refused [ form [ atom "max-underscores"; atom "many" ] ]);
          equal ~msg:"negative count" string
            {|max-underscores wants a non-negative count, not "-1"|}
            (refused [ form [ atom "max-underscores"; atom "-1" ] ]);
          equal ~msg:"duplicate count" string "max-underscores is set twice"
            (refused [ max_underscores 3; max_underscores 4 ]);
          equal ~msg:"arity" string
            "forbid-suffix wants exactly one argument: (forbid-suffix \
             <suffix>) or (max-underscores <count>)"
            (refused [ form [ atom "forbid-suffix"; atom "'"; atom "_" ] ]);
          equal ~msg:"unknown option" string
            {|unknown option "forbid-sufix" (did you mean "forbid-suffix"?)|}
            (refused [ form [ atom "forbid-sufix"; atom "'" ] ]);
          equal ~msg:"bare atom payload" string
            "expected (forbid-suffix <suffix>) or (max-underscores <count>)"
            (refused [ atom "forbid-suffix" ]));
    ]
