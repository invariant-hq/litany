(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Restricted_public_exception.rule
let mli_source = "fixtures/fix_rpe.ml"
let mli_cmt = "fixtures/.fix_rpe.objs/byte/fix_rpe.cmt"
let mli_cmti = "fixtures/.fix_rpe.objs/byte/fix_rpe.cmti"
let bare_source = "fixtures/fix_rpe_bare.ml"
let bare_cmt = "fixtures/.fix_rpe_bare.objs/byte/fix_rpe_bare.cmt"

let check_clean rep =
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep)

let finding_lines rep =
  List.map
    (fun (_, f) -> (Litany.Finding.loc f).Location.loc_start.Lexing.pos_lnum)
    (Litany.Engine.Report.findings rep)

let () =
  Windtrap.run "restricted-public-exception"
    [
      test "declares its one metadata record" (fun () ->
          equal string "restricted-public-exception" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "public mli-backed library: fires exactly on the marked exceptions"
        (fun () ->
          Support.check_markers rule ~kind:Litany.Roster.Library
            ~visibility:Litany.Roster.Public ~cmti:mli_cmti ~source:mli_source
            ~cmt:mli_cmt);
      test "unknown visibility is treated as public (the roster convention)"
        (fun () ->
          Support.check_markers rule ~kind:Litany.Roster.Library ~cmti:mli_cmti
            ~source:mli_source ~cmt:mli_cmt);
      test "public ml-only library: the derived signature is the surface"
        (fun () ->
          Support.check_markers rule ~kind:Litany.Roster.Library
            ~visibility:Litany.Roster.Public ~source:bare_source ~cmt:bare_cmt);
      test "messages name the exception" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Library
              ~visibility:Litany.Roster.Public ~cmti:mli_cmti ~source:mli_source
              ~cmt:mli_cmt
          in
          check_clean rep;
          equal (list string)
            [
              "exception Boom is declared in a public library interface; \
               return a result instead";
              "exception Rebound is declared in a public library interface; \
               return a result instead";
            ]
            (List.map
               (fun (_, f) -> Litany.Finding.message f)
               (Litany.Engine.Report.findings rep)));
      test "a private library is silent" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Library
              ~visibility:Litany.Roster.Private ~cmti:mli_cmti
              ~source:mli_source ~cmt:mli_cmt
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "an executable unit is silent" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Executable
              ~source:bare_source ~cmt:bare_cmt
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a test unit is silent" (fun () ->
          let rep =
            Support.report rule ~kind:Litany.Roster.Test ~source:bare_source
              ~cmt:bare_cmt
          in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
      test "a unit without kind metadata is silent" (fun () ->
          let rep = Support.report rule ~source:bare_source ~cmt:bare_cmt in
          check_clean rep;
          equal (list int) [] (finding_lines rep));
    ]
