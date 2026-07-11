(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The fixtures' bytes are pinned (fixtures/.ocamlformat-ignore):

   fix_mfn_bad.ml      "let value = 1 (* FIRE *)"  no final LF -> [24;24)
   fix_mfn_clean.ml    "let value = 1\n"    clean
   fix_mfn_crlf.ml     "let value = 1\r\n"  clean: the final byte is LF
   fix_mfn_crlf_bad.ml CRLF body, unterminated last line -> [38;38),
                       fix inserts \r\n (the file's own ending style)
   fix_mfn_empty.ml    ""                   clean: empty files have no lines *)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Missing_final_newline.rule

let fixture name =
  ( Printf.sprintf "fixtures/%s.ml" name,
    Printf.sprintf "fixtures/.%s.objs/byte/%s.cmt" name name )

let shape name =
  let source, cmt = fixture name in
  Support.shape (Support.report rule ~source ~cmt)

let () =
  Windtrap.run "missing-final-newline"
    [
      test "declares its one metadata record" (fun () ->
          equal string "missing-final-newline" (Rule.name rule);
          is_true ~msg:"group is Style" (Rule.group rule = Rule.Style);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Always" (Rule.fix rule = Rule.Always);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "reports the EOF insertion point of the unterminated file" (fun () ->
          equal
            (list (quad string string int int))
            [ ("missing-final-newline", "fixtures/fix_mfn_bad.ml", 24, 24) ]
            (shape "fix_mfn_bad"));
      test "reports the EOF insertion point of the unterminated CRLF file"
        (fun () ->
          equal
            (list (quad string string int int))
            [
              ("missing-final-newline", "fixtures/fix_mfn_crlf_bad.ml", 38, 38);
            ]
            (shape "fix_mfn_crlf_bad"));
      test "leaves LF, CRLF, and empty files clean" (fun () ->
          equal (list (quad string string int int)) [] (shape "fix_mfn_clean");
          equal (list (quad string string int int)) [] (shape "fix_mfn_crlf");
          equal (list (quad string string int int)) [] (shape "fix_mfn_empty"));
      test "fixes round-trip to the compiled golden" (fun () ->
          let source, cmt = fixture "fix_mfn_bad" in
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mfn_bad.fixed.ml");
      test "the CRLF fix matches the file's own ending style" (fun () ->
          (* A bare LF appended to a CRLF file leaves
             mixed endings; the fix inserts \r\n. *)
          let source, cmt = fixture "fix_mfn_crlf_bad" in
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_mfn_crlf_bad.fixed.ml");
      test "a terminal lone CR is not a final newline" (fun () ->
          (* Adopted from the prior implementation's suite: the
             last byte must be LF, so a file ending in a bare CR reports at
             the EOF insertion point. No compiled fixture can hold the byte
             (the lexer rejects a lone CR), so the rule's callback scans
             the crafted bytes directly. *)
          match Litany.Rule.callback rule with
          | Litany.Rule.Source f ->
              let text = "let x = 1\r" in
              let spans =
                List.map
                  (fun f ->
                    let l = Litany.Finding.loc f in
                    (l.Location.loc_start.pos_cnum, l.Location.loc_end.pos_cnum))
                  (f (Litany.Source.v ~path:"crafted.ml" text))
              in
              equal
                (list (pair int int))
                [ (String.length text, String.length text) ]
                spans
          | _ -> failf "missing-final-newline is not a source rule");
    ]
