(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Byte-exact goldens for the machine formats (json, github) over reports
   from real engine runs — same fixture discipline as the text and compiler
   suites. The json cases pin the whole line including the trailer; the
   byte-string convention (lossy + hex twin) is exercised through a fix
   whose replacement text is not valid UTF-8 — the one byte-string channel a
   test can drive without a non-UTF-8 filename, which APFS refuses to
   create. *)

open Windtrap
module Engine = Litany.Engine
module Rule = Litany.Rule
module Finding = Litany.Finding
module Entry = Litany.Roster.Entry

let plain_objs = "fixtures/engine/plain/.fix_engine.objs/byte"
let a_source = "fixtures/engine/plain/emit_a.ml"
let a_cmt = plain_objs ^ "/fix_engine__Emit_a.cmt"
let entry_a () = Entry.v ~source:a_source ~cmt:a_cmt ()
let entry_missing () = Entry.v ~source:"missing.ml" ~cmt:"missing.cmt" ()
let resolver = lazy (Litany.Naming.Resolver.create ~cmi_dirs:[ plain_objs ])

let load entry =
  Litany.Unit.load ~resolver:(Lazy.force resolver) ~build_current:true entry

let report ?(rules = []) entries =
  Engine.run ~rules ~catalog:rules ~roster:(Litany.Roster.v entries) ~load ()

let meta ?(group = Rule.Suspicious) ?(fix = Rule.Never) name =
  Rule.meta ~name ~group ~fix ~since:"1.0" ~summary:"test rule" ~doc:"test rule"
    ()

(* Emits once, on [41], the finding [make] builds from the constant's
   location. *)
let on_41 ?group ?fix name make =
  Rule.expr (meta ?group ?fix name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
          [ make e.Typedtree.exp_loc ]
      | _ -> [])

let render f rep =
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  f ppf rep;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let json = render Litany.Render.json
let github = render Litany.Render.github

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

let json_tests =
  group "json"
    [
      test "finding line with fix, then the trailer" (fun () ->
          let fixer =
            on_41 ~fix:Rule.Sometimes "fix-int" (fun loc ->
                Finding.v ~loc
                  ~fix:(Litany.Fix.safe_replace loc "42" ~title:"use 42")
                  "int constant")
          in
          equal string
            ("{\"rule\":\"fix-int\",\"severity\":\"warning\",\"file\":\"fixtures/engine/plain/emit_a.ml\",\"line\":1,\"col\":13,\"end_line\":1,\"end_col\":15,\"message\":\"int \
              constant\",\"fix\":{\"title\":\"use \
              42\",\"applicability\":\"safe\",\"edits\":[{\"start\":13,\"stop\":15,\"text\":\"42\"}]}}\n"
           ^ "{\"summary\":{\"schema\":1,\"rules_selected\":1,\"findings\":1,\"fixable\":1,\"units\":1,\"linted\":1,\"facts_only\":0,\"suppressed\":0,\"skipped\":[],\"failures\":[],\"degraded\":[],\"notes\":[],\"dropped\":0,\"roster\":[],\"exit\":1}}\n"
            )
            (json (report ~rules:[ fixer ] [ entry_a () ])));
      test "error severity from the correctness group" (fun () ->
          let flag =
            on_41 ~group:Rule.Correctness "err-int" (fun loc ->
                Finding.v ~loc "int constant")
          in
          let out = json (report ~rules:[ flag ] [ entry_a () ]) in
          let prefix = "{\"rule\":\"err-int\",\"severity\":\"error\"," in
          is_true
            (String.length out >= String.length prefix
            && String.sub out 0 (String.length prefix) = prefix));
      test "message escaping: quotes, backslash, newline, control" (fun () ->
          let flag =
            on_41 "esc" (fun loc ->
                Finding.v ~loc "say \"hi\"\\\nnext\tline \x01 end")
          in
          let out = json (report ~rules:[ flag ] [ entry_a () ]) in
          is_true
            (String.length out > 0
            &&
            let needle =
              "\"message\":\"say \\\"hi\\\"\\\\\\nnext\\tline \\u0001 end\""
            in
            let n = String.length out and m = String.length needle in
            let rec probe i =
              i + m <= n && (String.sub out i m = needle || probe (i + 1))
            in
            probe 0));
      test "non-UTF-8 fix text carries the reversible hex twin" (fun () ->
          let fixer =
            on_41 ~fix:Rule.Sometimes "raw-fix" (fun loc ->
                Finding.v ~loc
                  ~fix:
                    (Litany.Fix.safe_replace loc "caf\xe9" ~title:"raw bytes")
                  "int constant")
          in
          let out = json (report ~rules:[ fixer ] [ entry_a () ]) in
          is_true
            (let needle =
               "\"edits\":[{\"start\":13,\"stop\":15,\"text\":\"caf\xef\xbf\xbd\",\"text_bytes\":\"636166e9\"}]"
             in
             let n = String.length out and m = String.length needle in
             let rec probe i =
               i + m <= n && (String.sub out i m = needle || probe (i + 1))
             in
             probe 0));
      test "a clean report is the trailer alone" (fun () ->
          equal string
            "{\"summary\":{\"schema\":1,\"rules_selected\":0,\"findings\":0,\"fixable\":0,\"units\":1,\"linted\":1,\"facts_only\":0,\"suppressed\":0,\"skipped\":[],\"failures\":[],\"degraded\":[],\"notes\":[],\"dropped\":0,\"roster\":[],\"exit\":0}}\n"
            (json (report ~rules:[] [ entry_a () ])));
      test "skips land in the trailer with their reason slug" (fun () ->
          equal string
            "{\"summary\":{\"schema\":1,\"rules_selected\":0,\"findings\":0,\"fixable\":0,\"units\":1,\"linted\":1,\"facts_only\":0,\"suppressed\":0,\"skipped\":[{\"path\":\"missing.ml\",\"reason\":\"missing-artifact\"}],\"failures\":[],\"degraded\":[],\"notes\":[],\"dropped\":0,\"roster\":[],\"exit\":0}}\n"
            (json (report ~rules:[] [ entry_a (); entry_missing () ])));
      test "rule failures land in the trailer as records, exit 3" (fun () ->
          (* The exit-3 law's machine channel: a
             consumer that never parses the text page still sees which rule
             failed where, and the trailer's exit says the code hardened. *)
          let boom = Rule.expr (meta "boom") (fun _ _ -> failwith "kaboom") in
          equal string
            ("{\"summary\":{\"schema\":1,\"rules_selected\":1,\"findings\":0,\"fixable\":0,\"units\":1,\"linted\":1,\"facts_only\":0,\"suppressed\":0,\"skipped\":[],"
           ^ "\"failures\":[{\"rule\":\"boom\",\"path\":\"fixtures/engine/plain/emit_a.ml\",\"message\":\"Failure(\\\"kaboom\\\")\"}],"
           ^ "\"degraded\":[],\"notes\":[],\"dropped\":0,\"roster\":[],\"exit\":3}}\n"
            )
            (json (report ~rules:[ boom ] [ entry_a () ])));
    ]

let github_tests =
  group "github"
    [
      test "warning annotation: 1-based columns, fix appended" (fun () ->
          let fixer =
            on_41 ~fix:Rule.Sometimes "fix-int" (fun loc ->
                Finding.v ~loc
                  ~fix:(Litany.Fix.safe_replace loc "42" ~title:"use 42")
                  "int constant")
          in
          equal string
            "::warning \
             file=fixtures/engine/plain/emit_a.ml,line=1,col=14,endColumn=16,title=fix-int::int \
             constant fix (safe): use 42\n"
            (github (report ~rules:[ fixer ] [ entry_a () ])));
      test "error annotation from the correctness group" (fun () ->
          let flag =
            on_41 ~group:Rule.Correctness "err-int" (fun loc ->
                Finding.v ~loc "int constant")
          in
          equal string
            "::error \
             file=fixtures/engine/plain/emit_a.ml,line=1,col=14,endColumn=16,title=err-int::int \
             constant\n"
            (github (report ~rules:[ flag ] [ entry_a () ])));
      test "multi-line span: endLine, no columns" (fun () ->
          equal string
            "::warning \
             file=fixtures/engine/plain/emit_a.ml,line=1,endLine=2,title=span::spans \
             two lines\n"
            (github (report ~rules:[ two_line_span ] [ entry_a () ])));
      test "message escaping: percent and newline" (fun () ->
          let flag =
            on_41 "pct" (fun loc -> Finding.v ~loc "50% done\nnext: a,b")
          in
          equal string
            "::warning \
             file=fixtures/engine/plain/emit_a.ml,line=1,col=14,endColumn=16,title=pct::50%25 \
             done%0Anext: a,b\n"
            (github (report ~rules:[ flag ] [ entry_a () ])));
      test "a clean report renders zero bytes" (fun () ->
          equal string "" (github (report ~rules:[] [ entry_a () ])));
    ]

let () = Windtrap.run "litany_render_formats" [ json_tests; github_tests ]
