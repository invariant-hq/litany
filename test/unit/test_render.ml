(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Byte-exact goldens for the report page, over reports produced by real
   engine runs on the engine suite's compiled fixtures (fixtures/engine),
   and the grammar pin: every page is fed byte-for-byte to dune's vendored
   [ocamlc-loc] parser — the grammar oracle — which must recover every
   finding's path, line(s), chars, severity, and rule name with the
   excerpt, fix, summary, and roster lines present between and after the
   blocks. The fatal shapes the contract guards against (leading text, a
   caret row without a quoted line, a barred caret row, a styled header)
   are pinned as parser-failure proofs so the emitter's obligations keep
   their justification. *)

open Windtrap
module Engine = Litany.Engine
module Rule = Litany.Rule
module Finding = Litany.Finding
module Entry = Litany.Roster.Entry
module Ocamlc_loc = Vendor_ocamlc_loc.Ocamlc_loc

let plain_objs = "fixtures/engine/plain/.fix_engine.objs/byte"
let a_source = "fixtures/engine/plain/emit_a.ml"
let a_cmt = plain_objs ^ "/fix_engine__Emit_a.cmt"
let nope_source = "fixtures/engine/nope/wit_nope.ml"
let nope_cmt = "fixtures/engine/nope/.fix_nope.objs/byte/fix_nope__Wit_nope.cmt"
let nope_pp = "fixtures/engine/nope/wit_nope.pp.ml"
let entry_a () = Entry.v ~source:a_source ~cmt:a_cmt ()

let entry_nope () =
  Entry.v ~source:nope_source ~cmt:nope_cmt ~preprocessed_source:nope_pp ()

let entry_missing () = Entry.v ~source:"missing.ml" ~cmt:"missing.cmt" ()
let resolver = lazy (Litany.Naming.Resolver.create ~cmi_dirs:[ plain_objs ])

let load entry =
  Litany.Unit.load ~resolver:(Lazy.force resolver) ~build_current:true entry

let report ?(rules = []) entries =
  Engine.run ~rules ~catalog:rules ~roster:(Litany.Roster.v entries) ~load ()

let meta ?(group = Rule.Suspicious) ?(fix = Rule.Never) name =
  Rule.meta ~name ~group ~since:"1.0" ~fix ~summary:"test rule" ~doc:"test rule"
    ()

(* Emits on every int constant of the fixture ([41] and [1]). *)
let flag_int ?group ?(name = "flag-int") ?(message = "int constant") () =
  Rule.expr (meta ?group name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int _) ->
          [ Finding.v ~loc:e.exp_loc message ]
      | _ -> [])

(* Emits once, on [41], the finding [make] builds from the constant's
   location. *)
let on_41 ?fix name make =
  Rule.expr (meta ?fix name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
          [ make e.Typedtree.exp_loc ]
      | _ -> [])

let fixer =
  on_41 ~fix:Rule.Sometimes "fix-int" (fun loc ->
      Finding.v ~loc
        ~fix:(Litany.Fix.safe_replace loc "42" ~title:"use 42")
        "int constant")

(* A consistent span across the fixture's two lines, via a text rule (free
   of typed corroboration). *)
let two_line_span =
  Rule.source (meta "span") (fun src ->
      let path = Litany.Source.path src in
      let pos lnum bol cnum =
        {
          Lexing.pos_fname = path;
          pos_lnum = lnum;
          pos_bol = bol;
          pos_cnum = cnum;
        }
      in
      [
        Finding.v
          ~loc:
            {
              Location.loc_start = pos 1 0 4;
              loc_end = pos 2 20 23;
              loc_ghost = false;
            }
          "spans two lines";
      ])

let source_of_path path =
  if Sys.file_exists path then
    Some
      (Litany.Source.v ~path
         (In_channel.with_open_bin path In_channel.input_all))
  else None

let render ?color ?fixes ?(source_of_path = source_of_path) rep =
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  Litany.Render.text ?color ?fixes ~source_of_path ppf rep;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

(* One line per parsed report, byte-exact, so [equal (list string)] shows
   the whole round-trip in a failure. *)
let show_loc (l : Ocamlc_loc.loc) =
  let lines =
    match l.lines with
    | Ocamlc_loc.Single n -> string_of_int n
    | Ocamlc_loc.Range (a, b) -> Printf.sprintf "%d-%d" a b
  in
  let chars =
    match l.chars with None -> "?" | Some (a, b) -> Printf.sprintf "%d-%d" a b
  in
  Printf.sprintf "%s:%s:%s" l.path lines chars

let show_severity = function
  | Ocamlc_loc.Warning { Ocamlc_loc.code; name } ->
      Printf.sprintf "warning %d [%s]" code name
  | Ocamlc_loc.Error None -> "error"
  | Ocamlc_loc.Error (Some _) -> "error(structured)"
  | Ocamlc_loc.Alert { name; source } ->
      Printf.sprintf "alert %s %s" name source

let show_report (r : Ocamlc_loc.report) =
  Printf.sprintf "%s %s %S%s" (show_loc r.loc) (show_severity r.severity)
    r.message
    (String.concat ""
       (List.map
          (fun (l, m) -> Printf.sprintf " [related %s %S]" (show_loc l) m)
          r.related))

let parsed s = List.map show_report (Ocamlc_loc.parse s)

(* The locations alone — the grammar pin's unit of recovery. *)
let locations s =
  List.map (fun (r : Ocamlc_loc.report) -> show_loc r.loc) (Ocamlc_loc.parse s)

let a_loc chars = Printf.sprintf "fixtures/engine/plain/emit_a.ml:1:%s" chars

let golden_tests =
  group "goldens"
    [
      test "warning blocks with excerpt and carets, then the summary" (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             1 | let answer = 41 + 1\n\
            \                 ^^\n\
             Warning 0 [flag-int]: int constant\n\
             \032\032\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             1 | let answer = 41 + 1\n\
            \                      ^\n\
             Warning 0 [flag-int]: int constant\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render (report ~rules:[ flag_int () ] [ entry_a () ])));
      test "a clean run is the summary line alone" (fun () ->
          equal string
            "0 rules selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
             skipped\n"
            (render (report [ entry_a () ])));
      test "the fix line rides the block; the summary counts it" (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             1 | let answer = 41 + 1\n\
            \                 ^^\n\
             Warning 0 [fix-int]: int constant\n\
            \  fix (safe): use 42\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 1 finding (1 fixable \
             \xe2\x80\x94 run `litany check --fix`) \xc2\xb7 0 skipped\n"
            (render (report ~rules:[ fixer ] [ entry_a () ])));
      test "under --fix the hint yields to the applied count" (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             1 | let answer = 41 + 1\n\
            \                 ^^\n\
             Warning 0 [fix-int]: int constant\n\
            \  fix (safe): use 42\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 1 finding (1 fixable) \
             \xc2\xb7 0 fixes applied \xc2\xb7 0 skipped\n"
            (render ~fixes:(`Applied 0)
               (report ~rules:[ fixer ] [ entry_a () ])));
      test "suppressed findings count in the summary; notes follow it"
        (fun () ->
          let aliased =
            Rule.expr
              (Rule.meta ~name:"flag-int" ~renamed_from:[ "old-flag-int" ]
                 ~group:Rule.Suspicious ~since:"1.0" ~fix:Rule.Never
                 ~summary:"test rule" ~doc:"test rule" ()) (fun _ e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int _) ->
                    [ Finding.v ~loc:e.exp_loc "int constant" ]
                | _ -> [])
          in
          let ali_entry =
            Entry.v ~source:"fixtures/engine/allow/ali.ml"
              ~cmt:
                "fixtures/engine/allow/.fix_allow.objs/byte/fix_allow__Ali.cmt"
              ()
          in
          equal string
            "1 rule selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
             skipped \xc2\xb7 1 suppressed\n\
             note fixtures/engine/allow/ali.ml: suppression attribute names \
             \"old-flag-int\"; the rule is now \"flag-int\" \xe2\x80\x94 \
             update the attribute\n"
            (render (report ~rules:[ aliased ] [ ali_entry ])));
      test "skips are counted by reason" (fun () ->
          equal string
            "0 rules selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 1 \
             skipped (missing-artifact 1)\n"
            (render (report [ entry_a (); entry_missing () ])));
      test "an error-severity rule renders Error with the rule in the message"
        (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             1 | let answer = 41 + 1\n\
            \                 ^^\n\
             Error: int constant [flag-int]\n\
             \032\032\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             1 | let answer = 41 + 1\n\
            \                      ^\n\
             Error: int constant [flag-int]\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render
               (report
                  ~rules:[ flag_int ~group:Rule.Correctness () ]
                  [ entry_a () ])));
      test "no source, no excerpt: header and message alone" (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             Warning 0 [flag-int]: int constant\n\
             \032\032\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             Warning 0 [flag-int]: int constant\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render
               ~source_of_path:(fun _ -> None)
               (report ~rules:[ flag_int () ] [ entry_a () ])));
      test "a multi-line span is the lines L-M form, first line quoted"
        (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", lines 1-2, characters \
             4-3:\n\
             1 | let answer = 41 + 1\n\
            \        ^^^^^^^^^^^^^^^\n\
             Warning 0 [span]: spans two lines\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 1 finding \xc2\xb7 0 \
             skipped\n"
            (render (report ~rules:[ two_line_span ] [ entry_a () ])));
      test "multi-line messages continue indented under the severity line"
        (fun () ->
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             1 | let answer = 41 + 1\n\
            \                 ^^\n\
             Warning 0 [flag-int]: first\n\
            \    deeper\n\
            \  last\n\
             \032\032\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             1 | let answer = 41 + 1\n\
            \                      ^\n\
             Warning 0 [flag-int]: first\n\
            \    deeper\n\
            \  last\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render
               (report
                  ~rules:[ flag_int ~message:"first\n  deeper\nlast" () ]
                  [ entry_a () ])));
      test "line-anchored findings quote the line without carets" (fun () ->
          let r =
            Rule.expr (meta "bad-offsets") (fun u e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
                    let path = Litany.Unit.path u in
                    let pos cnum =
                      {
                        Lexing.pos_fname = path;
                        pos_lnum = 1;
                        pos_bol = 0;
                        pos_cnum = cnum;
                      }
                    in
                    let loc =
                      {
                        Location.loc_start = pos 100;
                        loc_end = pos 100;
                        loc_ghost = false;
                      }
                    in
                    [ Finding.v ~loc "offsets not trusted" ]
                | _ -> [])
          in
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters \
             100-100:\n\
             1 | let answer = 41 + 1\n\
             Warning 0 [bad-offsets]: offsets not trusted\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 1 finding \xc2\xb7 0 \
             skipped\n"
            (render (report ~rules:[ r ] [ entry_a () ])));
      test "dropped findings surface in the summary" (fun () ->
          let r =
            Rule.expr (meta "ghostly") (fun _ e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
                    [
                      Finding.v
                        ~loc:{ e.Typedtree.exp_loc with loc_ghost = true }
                        "ghost";
                    ]
                | _ -> [])
          in
          equal string
            "1 rule selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
             skipped \xc2\xb7 1 dropped\n"
            (render (report ~rules:[ r ] [ entry_a () ])));
      test "degradations are counted in the summary and listed under it"
        (fun () ->
          (* An attribute rule with no declared names demands the parse of
             every unit — the degradation probe. *)
          let attr = Rule.attribute (meta "attr") (fun _ _ -> []) in
          equal string
            ("1 rule selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
              skipped \xc2\xb7 1 degraded\n"
           ^ "degraded fixtures/engine/nope/wit_nope.ml: editable source does \
              not parse \xe2\x80\x94 attribute rules, attribute suppression, \
              and corroboration unavailable\n")
            (render (report ~rules:[ attr ] [ entry_nope () ])));
      test "no excerpt in a degraded unit: offsets cannot be trusted" (fun () ->
          (* Corroboration was waived, so the typed offsets count
             preprocessed bytes — here they land inside the editable
             file's #define line, and an excerpt would confidently caret
             bytes the finding never touched. Header and message alone. *)
          equal string
            ("File \"fixtures/engine/nope/wit_nope.ml\", line 1, characters \
              12-14:\n\
              Warning 0 [flag-int]: int constant\n\
              \032\032\n\
              File \"fixtures/engine/nope/wit_nope.ml\", line 1, characters \
              17-18:\n\
              Warning 0 [flag-int]: int constant\n\n\
              1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
              skipped \xc2\xb7 1 degraded\n"
           ^ "degraded fixtures/engine/nope/wit_nope.ml: editable source does \
              not parse \xe2\x80\x94 attribute rules, attribute suppression, \
              and corroboration unavailable\n")
            (render (report ~rules:[ flag_int () ] [ entry_nope () ])));
      test "rule failures are listed under the summary" (fun () ->
          let bomb = Rule.expr (meta "bomb") (fun _ _ -> failwith "boom") in
          equal string
            ("1 rule selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
              skipped\n"
           ^ "rule bomb failed on fixtures/engine/plain/emit_a.ml: \
              Failure(\"boom\")\n")
            (render (report ~rules:[ bomb ] [ entry_a () ])));
    ]

let color_tests =
  group "color"
    [
      test "color styles the severity word and the carets, never the header"
        (fun () ->
          let out =
            render ~color:true (report ~rules:[ flag_int () ] [ entry_a () ])
          in
          contains ~sub:"\027[33mWarning\027[0m 0 [flag-int]: int constant\n"
            out;
          contains ~sub:"\n                 \027[33m^^\027[0m\n" out;
          contains
            ~sub:
              "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters \
               13-15:\n"
            out);
      test "errors paint red" (fun () ->
          contains ~sub:"\027[31mError\027[0m: int constant [flag-int]\n"
            (render ~color:true
               (report
                  ~rules:[ flag_int ~group:Rule.Correctness () ]
                  [ entry_a () ])));
      test "no color by default" (fun () ->
          not_contains ~sub:"\027["
            (render (report ~rules:[ flag_int () ] [ entry_a () ])));
    ]

(* The grammar pin: whole pages — excerpts, fix lines, summary, roster and
   note lines included — through dune's vendored parser, which must
   recover every finding. Counting recovered locations against the
   findings rendered is the proof that no excerpt, summary, or roster
   line was mistaken for a location (each would have surfaced as an extra
   report or, worse, ended the stream). *)
let grammar_tests =
  group "grammar pin"
    [
      test
        "every block of a multi-finding page is recovered; trailing lines fold \
         into the last message" (fun () ->
          let out = render (report ~rules:[ flag_int () ] [ entry_a () ]) in
          equal (list string)
            [
              a_loc "13-15" ^ " warning 0 [flag-int] \"int constant\"";
              a_loc "18-19"
              ^ " warning 0 [flag-int] \"int constant\\n\\n1 rule selected \
                 \\194\\183 1 unit \\194\\183 2 findings \\194\\183 0 \
                 skipped\"";
            ]
            (parsed out));
      test "the fix line folds into its finding's message" (fun () ->
          let out = render (report ~rules:[ fixer ] [ entry_a () ]) in
          let only =
            match Ocamlc_loc.parse out with [ r ] -> r | _ -> assert false
          in
          equal string (a_loc "13-15") (show_loc only.loc);
          equal string "warning 0 [fix-int]" (show_severity only.severity);
          is_true
            (String.starts_with ~prefix:"int constant\n  fix (safe): use 42\n"
               only.message));
      test "errors parse as errors with the rule in the message" (fun () ->
          let out =
            render
              (report
                 ~rules:[ flag_int ~group:Rule.Correctness () ]
                 [ entry_a () ])
          in
          let reports = Ocamlc_loc.parse out in
          equal (list string) [ a_loc "13-15"; a_loc "18-19" ] (locations out);
          equal (list string) [ "error"; "error" ]
            (List.map
               (fun (r : Ocamlc_loc.report) -> show_severity r.severity)
               reports);
          is_true
            (List.for_all
               (fun (r : Ocamlc_loc.report) ->
                 String.starts_with ~prefix:"int constant [flag-int]" r.message)
               reports));
      test "multi-line messages survive the parser's indent normalization"
        (fun () ->
          let out =
            render
              (report
                 ~rules:[ flag_int ~message:"first\n  deeper\nlast" () ]
                 [ entry_a () ])
          in
          let reports = Ocamlc_loc.parse out in
          equal (list string) [ a_loc "13-15"; a_loc "18-19" ] (locations out);
          equal string "first\n  deeper\nlast"
            (List.hd reports).Ocamlc_loc.message);
      test "a multi-line span is the lines L-M form" (fun () ->
          let out = render (report ~rules:[ two_line_span ] [ entry_a () ]) in
          equal (list string)
            [ "fixtures/engine/plain/emit_a.ml:1-2:4-3" ]
            (locations out));
      test "a message line forging a File header is defused, not fatal"
        (fun () ->
          let out =
            render
              (report
                 ~rules:
                   [
                     flag_int
                       ~message:
                         "see the copy\n\
                          \032\032\n\
                          File \"other.ml\", line 3, characters 0-4:\n\
                          trailing text"
                       ();
                   ]
                 [ entry_a () ])
          in
          (* The forged header gained a second space after [File], so the
             lexer no longer recognizes it; both findings survive and
             nothing lands in [related]. *)
          contains ~sub:"  File  \"other.ml\", line 3, characters 0-4:\n" out;
          equal (list string) [ a_loc "13-15"; a_loc "18-19" ] (locations out);
          is_true
            (List.for_all
               (fun (r : Ocamlc_loc.report) -> r.related = [])
               (Ocamlc_loc.parse out)));
      test "pages without excerpts parse the same" (fun () ->
          equal (list string)
            [ a_loc "13-15"; a_loc "18-19" ]
            (locations
               (render
                  ~source_of_path:(fun _ -> None)
                  (report ~rules:[ flag_int () ] [ entry_a () ]))));
      test "a quoted line without carets is skipped as an excerpt" (fun () ->
          let r =
            Rule.expr (meta "bad-offsets") (fun u e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
                    let path = Litany.Unit.path u in
                    let pos cnum =
                      {
                        Lexing.pos_fname = path;
                        pos_lnum = 1;
                        pos_bol = 0;
                        pos_cnum = cnum;
                      }
                    in
                    [
                      Finding.v
                        ~loc:
                          {
                            Location.loc_start = pos 100;
                            loc_end = pos 100;
                            loc_ghost = false;
                          }
                        "offsets not trusted";
                    ]
                | _ -> [])
          in
          equal (list string)
            [ a_loc "100-100" ]
            (locations (render (report ~rules:[ r ] [ entry_a () ]))));
      test
        "a degraded unit's page — no excerpts, degraded line after the summary \
         — parses" (fun () ->
          equal (list string)
            [
              "fixtures/engine/nope/wit_nope.ml:1:12-14";
              "fixtures/engine/nope/wit_nope.ml:1:17-18";
            ]
            (locations
               (render (report ~rules:[ flag_int () ] [ entry_nope () ]))));
      test "a clean page has no location" (fun () ->
          equal (list string) [] (locations (render (report [ entry_a () ]))));
    ]

(* The fatal shapes, pinned so the emitter's obligations — nothing before
   the first block, ocamlc's excerpt shape between header and severity
   line, a plain header — keep their justification: each one demonstrably
   destroys findings in dune. *)
let block =
  "File \"a.ml\", line 1, characters 0-3:\nWarning 0 [some-rule]: the message\n"

let failure_proof_tests =
  group "parser-failure proofs"
    [
      test "leading text discards every finding, not just the prefix" (fun () ->
          equal (list string) [] (parsed ("scanning 34 units\n" ^ block)));
      test "a caret row without a quoted line kills the block and the rest"
        (fun () ->
          equal (list string) []
            (parsed
               ("File \"a.ml\", line 1, characters 0-3:\n\
                \  ^^^\n\
                 Warning 0 [some-rule]: the message\n" ^ block)));
      test "a barred caret row is not an excerpt row: the stream ends there"
        (fun () ->
          equal (list string) []
            (parsed
               ("File \"a.ml\", line 1, characters 0-3:\n\
                 1 | let\n\
                \  | ^^^\n\
                 Warning 0 [some-rule]: the message\n" ^ block)));
      test "a styled header is not a location" (fun () ->
          equal (list string) [] (parsed ("\027[1m" ^ block ^ block)));
      test "a styled caret row ends the stream: color is for terminals only"
        (fun () ->
          equal (list string) []
            (parsed
               ("File \"a.ml\", line 1, characters 0-3:\n\
                 1 | let\n\
                \    \027[33m^^^\027[0m\n\
                 Warning 0 [some-rule]: the message\n" ^ block)));
      test "a trailing summary folds into the last finding's message" (fun () ->
          equal (list string)
            [ "a.ml:1:0-3 warning 0 [some-rule] \"the message\\n1 finding.\"" ]
            (parsed (block ^ "1 finding.\n")));
    ]

let () =
  Windtrap.run "litany_render"
    [ golden_tests; color_tests; grammar_tests; failure_proof_tests ]
