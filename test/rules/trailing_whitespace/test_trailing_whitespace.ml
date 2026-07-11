(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The fixture's bytes are pinned (fixtures/.ocamlformat-ignore); each
   positive line carries a FIRE marker before its whitespace run:

   line 1  "let a = 1 (* FIRE *)␣␣"    two trailing spaces      -> [20;22)
   line 2  "let b = 2"                 clean
   line 3  "let c = 3 (* FIRE *)⇥"     trailing tab             -> [53;54)
   line 4  "let d = 4 (* FIRE *)␣" CRLF  run ends before the CR -> [75;76)
   line 5  "let e = 5"                 clean
   line 6  "let f = 6 (* FIRE *)␣"     run ends before the LF   -> [108;109)

   Adopted from the prior implementation's suite:
   line 7  "␣⇥"                        whitespace-only line     -> [110;112)
   line 8  "let g = "0xFF"␣⇥"          invalid UTF-8 scanned
                                       byte-wise, run reported  -> [124;126)
   line 9  "let h = 8" EOF             clean final line

   The lone-CR cases (ws before a lone CR is interior; ws between a lone CR
   and EOF is a run) cannot compile — the OCaml lexer rejects a bare CR
   outside literals — so they are pinned below through the rule's own
   callback over crafted bytes — the harness shape text rules need. *)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Trailing_whitespace.rule
let source = "fixtures/fix_tws.ml"
let cmt = "fixtures/.fix_tws.objs/byte/fix_tws.cmt"

let () =
  Windtrap.run "trailing-whitespace"
    [
      test "declares its one metadata record" (fun () ->
          equal string "trailing-whitespace" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"fix promise is Always" (Rule.fix rule = Rule.Always);
          equal string "1.0" (Rule.since rule));
      test "spans exactly the whitespace runs before LF, CRLF, and EOF"
        (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal
            (list (quad string string int int))
            [
              ("trailing-whitespace", source, 20, 22);
              ("trailing-whitespace", source, 53, 54);
              ("trailing-whitespace", source, 75, 76);
              ("trailing-whitespace", source, 108, 109);
              ("trailing-whitespace", source, 110, 112);
              ("trailing-whitespace", source, 124, 126);
            ]
            (Support.shape rep);
          equal int 1 (Litany.Engine.Report.exit_code rep));
      test "lone-CR bytes: ws before is interior, ws after runs to EOF"
        (fun () ->
          (* Adopted coverage over bytes no compiled fixture can hold
             (the lexer rejects a bare CR): the rule's callback scans
             crafted sources directly. *)
          let scan text =
            match Litany.Rule.callback rule with
            | Litany.Rule.Source f ->
                List.map
                  (fun f ->
                    let l = Litany.Finding.loc f in
                    (l.Location.loc_start.pos_cnum, l.Location.loc_end.pos_cnum))
                  (f (Litany.Source.v ~path:"crafted.ml" text))
            | _ -> failf "trailing-whitespace is not a source rule"
          in
          (* Whitespace before a lone CR never reaches a line end: clean. *)
          equal (list (pair int int)) [] (scan "x \ry\n");
          equal (list (pair int int)) [] (scan "x \r");
          (* Whitespace between a lone CR and EOF is a run, reported to
             EOF. *)
          equal (list (pair int int)) [ (2, 4) ] (scan "x\r \t"));
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_tws.fixed.ml");
    ]
