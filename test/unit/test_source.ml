(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Source = Litany.Source
module Span = Litany.Span

let span = Testable.make ~pp:Span.pp ~equal:Span.equal

let pp_position ppf (p : Lexing.position) =
  Format.fprintf ppf "{fname=%S; lnum=%d; bol=%d; cnum=%d}" p.pos_fname
    p.pos_lnum p.pos_bol p.pos_cnum

let equal_position (p : Lexing.position) (p' : Lexing.position) =
  String.equal p.pos_fname p'.pos_fname
  && p.pos_lnum = p'.pos_lnum && p.pos_bol = p'.pos_bol
  && p.pos_cnum = p'.pos_cnum

let position_t = Testable.make ~pp:pp_position ~equal:equal_position
let src contents = Source.v ~path:"test.ml" contents

(* LF-heavy text exercises the line index; plain letters exercise the
   degenerate single-line case. *)
let gen_contents =
  Gen.string_of
    (Gen.frequency [ (3, Gen.char_range 'a' 'z'); (1, Gen.constant '\n') ])

(* Bounded variant for the properties that pair a naive quadratic oracle
   with a loop over every offset. *)
let gen_short_contents =
  Gen.string_of ~size:(Gen.int_range 0 60)
    (Gen.frequency [ (3, Gen.char_range 'a' 'z'); (1, Gen.constant '\n') ])

(* The number of lines by the mli's definition, derived independently of the
   line index: split on LF, and a trailing LF closes the last line rather
   than opening a new one. *)
let naive_lines contents =
  if contents = "" then 0
  else
    let parts = List.length (String.split_on_char '\n' contents) in
    if contents.[String.length contents - 1] = '\n' then parts - 1 else parts

(* Greatest line start [<= off], by linear scan over the naive start list —
   the oracle the O(log n) index must agree with. *)
let naive_line_of_offset contents off =
  let len = String.length contents in
  let starts = ref [ 0 ] in
  String.iteri
    (fun i c -> if c = '\n' && i + 1 < len then starts := (i + 1) :: !starts)
    contents;
  let best_line = ref 1 and best_start = ref 0 in
  List.iteri
    (fun i start ->
      if start <= off && start >= !best_start then begin
        best_line := i + 1;
        best_start := start
      end)
    (List.rev !starts);
  (!best_line, !best_start)

let accessors =
  group "accessors"
    [
      test "path and contents are kept verbatim" (fun () ->
          let s = Source.v ~path:"lib/foo.ml" "let x = 1\n" in
          equal string "lib/foo.ml" (Source.path s);
          equal string "let x = 1\n" (Source.contents s));
      test "length counts bytes" (fun () ->
          equal int 0 (Source.length (src ""));
          equal int 4 (Source.length (src "a\nb\n")));
    ]

let lines_and_line =
  group "lines"
    [
      cases
        ~name:(fun (contents, _) -> Printf.sprintf "%S" contents)
        "line count"
        [
          ("", 0);
          ("a", 1);
          ("\n", 1);
          ("a\n", 1);
          ("a\nb", 2);
          ("a\nb\n", 2);
          ("a\n\nb", 3);
          ("\n\n", 2);
        ]
        (fun (contents, expected) ->
          equal int expected (Source.lines (src contents)));
      test "line spans exclude the trailing LF" (fun () ->
          let s = src "a\nb\n" in
          equal (option span) (Some (Span.v ~start:0 ~stop:1)) (Source.line s 1);
          equal (option span) (Some (Span.v ~start:2 ~stop:3)) (Source.line s 2));
      test "an empty line is an empty span" (fun () ->
          let s = src "a\n\nb" in
          equal (option span) (Some (Span.v ~start:2 ~stop:2)) (Source.line s 2));
      test "a final line without trailing LF runs to the end" (fun () ->
          let s = src "a\nbc" in
          equal (option span) (Some (Span.v ~start:2 ~stop:4)) (Source.line s 2));
      test "out-of-range line numbers are None" (fun () ->
          let s = src "a\nb" in
          equal (option span) None (Source.line s 0);
          equal (option span) None (Source.line s 3);
          equal (option span) None (Source.line (src "") 1));
      prop "line count agrees with the split-on-LF oracle" gen_contents
        (fun contents ->
          equal int (naive_lines contents) (Source.lines (src contents)));
      prop "line slices agree with split_on_char" gen_contents (fun contents ->
          let s = src contents in
          let parts = String.split_on_char '\n' contents in
          for n = 1 to Source.lines s do
            let sp = require_some ~msg:(string_of_int n) (Source.line s n) in
            equal string
              ~msg:(Printf.sprintf "line %d" n)
              (List.nth parts (n - 1))
              (require_some (Source.slice s sp))
          done);
    ]

let slicing =
  group "slice"
    [
      prop "agrees with String.sub inside the bounds"
        Gen.(pair gen_contents (pair (int_range 0 40) (int_range 0 40)))
        (fun (contents, (a, b)) ->
          let s = src contents in
          let start = min a b and stop = max a b in
          let sp = Span.v ~start ~stop in
          let expected =
            if stop <= String.length contents then
              Some (String.sub contents start (stop - start))
            else None
          in
          equal (option string) expected (Source.slice s sp));
      test "the whole-source span slices to the contents" (fun () ->
          let s = src "a\nb\n" in
          equal (option string) (Some "a\nb\n")
            (Source.slice s (Span.v ~start:0 ~stop:4)));
      test "an empty span at the end slices to the empty string" (fun () ->
          equal (option string) (Some "")
            (Source.slice (src "ab") (Span.v ~start:2 ~stop:2)));
      test "a span past the end is None, not an error" (fun () ->
          equal (option string) None
            (Source.slice (src "ab") (Span.v ~start:0 ~stop:3)));
    ]

let positions =
  group "position"
    [
      test "populates every field from the line index" (fun () ->
          let s = src "a\nbc" in
          equal (option position_t)
            (Some
               {
                 Lexing.pos_fname = "test.ml";
                 pos_lnum = 2;
                 pos_bol = 2;
                 pos_cnum = 3;
               })
            (Source.position s 3));
      test "an LF belongs to the line it ends" (fun () ->
          let s = src "a\nb" in
          let p = require_some (Source.position s 1) in
          equal int 1 p.Lexing.pos_lnum);
      test "the offset one past the end is on the last line" (fun () ->
          let s = src "a\nb" in
          let p = require_some (Source.position s 3) in
          equal int 2 p.Lexing.pos_lnum;
          equal int 2 p.Lexing.pos_bol);
      test "the empty source has offset 0 on line 1" (fun () ->
          equal (option position_t)
            (Some
               {
                 Lexing.pos_fname = "test.ml";
                 pos_lnum = 1;
                 pos_bol = 0;
                 pos_cnum = 0;
               })
            (Source.position (src "") 0));
      test "out-of-bounds offsets are None" (fun () ->
          let s = src "ab" in
          equal (option position_t) None (Source.position s (-1));
          equal (option position_t) None (Source.position s 3));
      prop "the line index agrees with a naive linear scan" gen_short_contents
        (fun contents ->
          let s = src contents in
          if contents <> "" then
            for off = 0 to String.length contents do
              let p = require_some (Source.position s off) in
              let lnum, bol = naive_line_of_offset contents off in
              equal int
                ~msg:(Printf.sprintf "lnum at %d" off)
                lnum p.Lexing.pos_lnum;
              equal int
                ~msg:(Printf.sprintf "bol at %d" off)
                bol p.Lexing.pos_bol
            done);
    ]

let locations =
  group "location"
    [
      test "is non-ghost and fully populated" (fun () ->
          let s = src "a\nbc" in
          let loc =
            require_some (Source.location s (Span.v ~start:0 ~stop:3))
          in
          is_false loc.Location.loc_ghost;
          equal position_t
            {
              Lexing.pos_fname = "test.ml";
              pos_lnum = 1;
              pos_bol = 0;
              pos_cnum = 0;
            }
            loc.Location.loc_start;
          equal position_t
            {
              Lexing.pos_fname = "test.ml";
              pos_lnum = 2;
              pos_bol = 2;
              pos_cnum = 3;
            }
            loc.Location.loc_end);
      test "a span past the end is None" (fun () ->
          equal
            (option (Testable.make ~pp:Location.print_loc ~equal:( = )))
            None
            (Source.location (src "ab") (Span.v ~start:0 ~stop:3)));
      prop "inverts Litany.Span.of_location"
        Gen.(pair gen_contents (pair (int_range 0 40) (int_range 0 40)))
        (fun (contents, (a, b)) ->
          let s = src contents in
          let sp = Span.v ~start:(min a b) ~stop:(max a b) in
          if Span.stop sp <= Source.length s then
            let loc = require_some (Source.location s sp) in
            equal span sp (Span.of_location loc));
    ]

let consistency =
  group "consistent"
    [
      prop "holds for every position the index itself produces"
        gen_short_contents (fun contents ->
          let s = src contents in
          if Source.lines s > 0 then
            for off = 0 to String.length contents do
              let p = require_some (Source.position s off) in
              is_true
                ~msg:(Printf.sprintf "offset %d" off)
                (Source.consistent s p)
            done);
      test "accepts the line stop including its LF, inclusively" (fun () ->
          let s = src "ab\ncd\n" in
          let at ~lnum ~bol ~cnum =
            {
              Lexing.pos_fname = "test.ml";
              pos_lnum = lnum;
              pos_bol = bol;
              pos_cnum = cnum;
            }
          in
          is_true (Source.consistent s (at ~lnum:1 ~bol:0 ~cnum:3));
          is_false (Source.consistent s (at ~lnum:1 ~bol:0 ~cnum:4)));
      test "rejects a line-directive-style rewritten position" (fun () ->
          (* A textual preprocessor emitted [# 42 "gen.ml"]: pos_lnum was
             rewritten while pos_cnum kept counting preprocessed-file bytes.
             Against the editable source neither the line number nor the
             derived bol can agree. *)
          let s = src "let x = 1\nlet y = 2\n" in
          let forged =
            {
              Lexing.pos_fname = "gen.ml";
              pos_lnum = 42;
              pos_bol = 0;
              pos_cnum = 3;
            }
          in
          is_false (Source.consistent s forged));
      test "rejects a bol that is not the line's start" (fun () ->
          let s = src "ab\ncd\n" in
          is_false
            (Source.consistent s
               {
                 Lexing.pos_fname = "test.ml";
                 pos_lnum = 2;
                 pos_bol = 0;
                 pos_cnum = 4;
               }));
      test "rejects a cnum outside the claimed line" (fun () ->
          let s = src "ab\ncd\nef\n" in
          let p ~cnum =
            {
              Lexing.pos_fname = "test.ml";
              pos_lnum = 1;
              pos_bol = 0;
              pos_cnum = cnum;
            }
          in
          is_false (Source.consistent s (p ~cnum:7));
          is_false (Source.consistent s (p ~cnum:(-1))));
      test "nothing is consistent with an empty source" (fun () ->
          is_false
            (Source.consistent (src "")
               {
                 Lexing.pos_fname = "test.ml";
                 pos_lnum = 1;
                 pos_bol = 0;
                 pos_cnum = 0;
               }));
    ]

let () =
  run "litany_source"
    [ accessors; lines_and_line; slicing; positions; locations; consistency ]
