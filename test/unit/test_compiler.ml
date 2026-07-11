(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Goldens for the compiler renderer, spike-B style: every rendered report
   is fed byte-for-byte to dune's vendored [ocamlc-loc] parser and the
   parsed reports must round-trip rule name, path, line(s), chars, severity,
   and message. The three fatal grammar shapes — leading text, a caret line
   without an excerpt, a trailing summary — are pinned as parser-failure
   proofs so the emitter's "nothing but blocks" contract stays honest. *)

open Windtrap
module Engine = Litany.Engine
module Rule = Litany.Rule
module Finding = Litany.Finding
module Entry = Litany.Roster.Entry
module Ocamlc_loc = Vendor_ocamlc_loc.Ocamlc_loc

let plain_objs = "fixtures/engine/plain/.fix_engine.objs/byte"
let a_source = "fixtures/engine/plain/emit_a.ml"
let a_cmt = plain_objs ^ "/fix_engine__Emit_a.cmt"
let entry_a () = Entry.v ~source:a_source ~cmt:a_cmt ()
let resolver = lazy (Litany.Naming.Resolver.create ~cmi_dirs:[ plain_objs ])

let load entry =
  Litany.Unit.load ~resolver:(Lazy.force resolver) ~build_current:true entry

let report ~rules entries =
  Engine.run ~rules ~catalog:rules ~roster:(Litany.Roster.v entries) ~load ()

let meta ?(group = Rule.Suspicious) name =
  Rule.meta ~name ~group ~since:"1.0" ~fix:Rule.Never ~summary:"test rule"
    ~doc:"test rule" ()

(* Emits on every int constant of the fixture ([41] and [1]). *)
let flag_int ?group ?(message = "int constant") () =
  Rule.expr (meta ?group "flag-int") (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int _) ->
          [ Finding.v ~loc:e.exp_loc message ]
      | _ -> [])

(* Emits once, on [41], with the finding [make] builds from the unit path
   and the constant's location. *)
let on_41 name make =
  Rule.expr (meta name) (fun u e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
          [ make (Litany.Unit.path u) e.Typedtree.exp_loc ]
      | _ -> [])

let render rep =
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  Litany.Render.compiler ppf rep;
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

let round_trip_tests =
  group "round-trip"
    [
      test "warnings: byte-exact blocks, and the parser recovers everything"
        (fun () ->
          let out = render (report ~rules:[ flag_int () ] [ entry_a () ]) in
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             Warning 0 [flag-int]: int constant\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             Warning 0 [flag-int]: int constant\n"
            out;
          equal (list string)
            [
              "fixtures/engine/plain/emit_a.ml:1:13-15 warning 0 [flag-int] \
               \"int constant\"";
              "fixtures/engine/plain/emit_a.ml:1:18-19 warning 0 [flag-int] \
               \"int constant\"";
            ]
            (parsed out));
      test "errors carry the rule name inside the message" (fun () ->
          let out =
            render
              (report
                 ~rules:[ flag_int ~group:Rule.Correctness () ]
                 [ entry_a () ])
          in
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 13-15:\n\
             Error: int constant [flag-int]\n\
             File \"fixtures/engine/plain/emit_a.ml\", line 1, characters 18-19:\n\
             Error: int constant [flag-int]\n"
            out;
          equal (list string)
            [
              "fixtures/engine/plain/emit_a.ml:1:13-15 error \"int constant \
               [flag-int]\"";
              "fixtures/engine/plain/emit_a.ml:1:18-19 error \"int constant \
               [flag-int]\"";
            ]
            (parsed out));
      test "multi-line messages survive the parser's indent normalization"
        (fun () ->
          let out =
            render
              (report
                 ~rules:[ flag_int ~message:"first\n  deeper\nlast" () ]
                 [ entry_a () ])
          in
          contains ~sub:"Warning 0 [flag-int]: first\n    deeper\n  last\n" out;
          equal (list string)
            [
              "fixtures/engine/plain/emit_a.ml:1:13-15 warning 0 [flag-int] \
               \"first\\n  deeper\\nlast\"";
              "fixtures/engine/plain/emit_a.ml:1:18-19 warning 0 [flag-int] \
               \"first\\n  deeper\\nlast\"";
            ]
            (parsed out));
      test "a multi-line span is the lines L-M form" (fun () ->
          (* A text rule: free to anchor a (consistent) span across both
             fixture lines — typed corroboration does not gate it. *)
          let span =
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
          in
          let out = render (report ~rules:[ span ] [ entry_a () ]) in
          equal string
            "File \"fixtures/engine/plain/emit_a.ml\", lines 1-2, characters \
             4-3:\n\
             Warning 0 [span]: spans two lines\n"
            out;
          equal (list string)
            [
              "fixtures/engine/plain/emit_a.ml:1-2:4-3 warning 0 [span] \
               \"spans two lines\"";
            ]
            (parsed out));
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
          equal (list string)
            [
              "fixtures/engine/plain/emit_a.ml:1:13-15 warning 0 [flag-int] \
               \"see the copy\\nFile  \\\"other.ml\\\", line 3, characters \
               0-4:\\ntrailing text\"";
              "fixtures/engine/plain/emit_a.ml:1:18-19 warning 0 [flag-int] \
               \"see the copy\\nFile  \\\"other.ml\\\", line 3, characters \
               0-4:\\ntrailing text\"";
            ]
            (parsed out));
      test "a clean report renders zero bytes" (fun () ->
          equal string "" (render (report ~rules:[] [ entry_a () ])));
    ]

(* The three fatal shapes, pinned so the emitter contract —
   nothing before the first block, no caret lines, no summary — keeps its
   justification: each one demonstrably destroys findings in dune. *)
let block =
  "File \"a.ml\", line 1, characters 0-3:\nWarning 0 [some-rule]: the message\n"

let failure_proof_tests =
  group "parser-failure proofs"
    [
      test "leading text discards every finding, not just the prefix" (fun () ->
          equal (list string) [] (parsed ("scanning 34 units\n" ^ block)));
      test "a caret line without an excerpt kills the block and the rest"
        (fun () ->
          equal (list string) []
            (parsed
               ("File \"a.ml\", line 1, characters 0-3:\n\
                \  ^^^\n\
                 Warning 0 [some-rule]: the message\n" ^ block)));
      test "a trailing summary corrupts the last finding's message" (fun () ->
          equal (list string)
            [ "a.ml:1:0-3 warning 0 [some-rule] \"the message\\n1 finding.\"" ]
            (parsed (block ^ "1 finding.\n")));
    ]

let () =
  Windtrap.run "litany_render_compiler"
    [ round_trip_tests; failure_proof_tests ]
