(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Byte-exact goldens for the text renderer, over reports produced by real
   engine runs on the engine suite's compiled fixtures (fixtures/engine). The expected strings are
   the committed goldens; every one is compared with [equal string]. *)

open Windtrap
module Engine = Litany.Engine
module Rule = Litany.Rule
module Finding = Litany.Finding
module Entry = Litany.Roster.Entry

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

let meta ?(group = Rule.Suspicious) name =
  Rule.meta ~name ~group ~since:"1.0" ~fix:Rule.Never ~summary:"test rule"
    ~doc:"test rule" ()

let flag_int ?group ?(name = "flag-int") () =
  Rule.expr (meta ?group name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int _) ->
          [ Finding.v ~loc:e.exp_loc "int constant" ]
      | _ -> [])

let source_of_path path =
  if Sys.file_exists path then
    Some
      (Litany.Source.v ~path
         (In_channel.with_open_bin path In_channel.input_all))
  else None

let render ?color ?(source_of_path = source_of_path) rep =
  let buf = Buffer.create 256 in
  let ppf = Format.formatter_of_buffer buf in
  Litany.Render.text ?color ~source_of_path ppf rep;
  Format.pp_print_flush ppf ();
  Buffer.contents buf

let golden_tests =
  group "goldens"
    [
      test "warning findings with carets, then the summary" (fun () ->
          equal string
            "fixtures/engine/plain/emit_a.ml:1:14 warning flag-int\n\
            \  int constant\n\
            \     1 | let answer = 41 + 1\n\
            \       |              ^^\n\
             fixtures/engine/plain/emit_a.ml:1:19 warning flag-int\n\
            \  int constant\n\
            \     1 | let answer = 41 + 1\n\
            \       |                   ^\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render (report ~rules:[ flag_int () ] [ entry_a () ])));
      test "a clean run is the summary line alone" (fun () ->
          equal string
            "0 rules selected \xc2\xb7 1 unit \xc2\xb7 0 findings \xc2\xb7 0 \
             skipped\n"
            (render (report [ entry_a () ])));
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
      test "an error-severity rule renders error" (fun () ->
          equal string
            "fixtures/engine/plain/emit_a.ml:1:14 error flag-int\n\
            \  int constant\n\
            \     1 | let answer = 41 + 1\n\
            \       |              ^^\n\
             fixtures/engine/plain/emit_a.ml:1:19 error flag-int\n\
            \  int constant\n\
            \     1 | let answer = 41 + 1\n\
            \       |                   ^\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render
               (report
                  ~rules:[ flag_int ~group:Rule.Correctness () ]
                  [ entry_a () ])));
      test "no source, no excerpt: location and message alone" (fun () ->
          equal string
            "fixtures/engine/plain/emit_a.ml:1:14 warning flag-int\n\
            \  int constant\n\
             fixtures/engine/plain/emit_a.ml:1:19 warning flag-int\n\
            \  int constant\n\n\
             1 rule selected \xc2\xb7 1 unit \xc2\xb7 2 findings \xc2\xb7 0 \
             skipped\n"
            (render
               ~source_of_path:(fun _ -> None)
               (report ~rules:[ flag_int () ] [ entry_a () ])));
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
            "fixtures/engine/plain/emit_a.ml:1:101 warning bad-offsets\n\
            \  offsets not trusted\n\
            \     1 | let answer = 41 + 1\n\n\
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
             bytes the finding never touched. Location and message alone. *)
          equal string
            ("fixtures/engine/nope/wit_nope.ml:1:13 warning flag-int\n\
             \  int constant\n\
              fixtures/engine/nope/wit_nope.ml:1:18 warning flag-int\n\
             \  int constant\n\n\
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
      test "color styles the severity word and the carets" (fun () ->
          let out =
            render ~color:true (report ~rules:[ flag_int () ] [ entry_a () ])
          in
          contains ~sub:"\027[33mwarning\027[0m" out;
          contains ~sub:"\027[33m^^\027[0m" out);
      test "no color by default" (fun () ->
          not_contains ~sub:"\027["
            (render (report ~rules:[ flag_int () ] [ entry_a () ])));
    ]

let () = Windtrap.run "litany_render" [ golden_tests; color_tests ]
