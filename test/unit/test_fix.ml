(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Fix = Litany.Fix
module Span = Litany.Span

let pos cnum =
  { Lexing.pos_fname = "a.ml"; pos_lnum = 1; pos_bol = 0; pos_cnum = cnum }

let loc start stop =
  { Location.loc_start = pos start; loc_end = pos stop; loc_ghost = false }

let edit ?(text = "x") start stop = { Fix.span = Span.v ~start ~stop; text }
let spans f = List.map (fun (e : Fix.edit) -> e.span) (Fix.edits f)
let span_t = Testable.make ~pp:Span.pp ~equal:Span.equal

let construction =
  group "construction"
    [
      test "v rejects an empty edit list" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"no edits") (fun () ->
              Fix.v ~title:"t" []));
      test "v rejects overlapping edits" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"overlap") (fun () ->
              Fix.v ~title:"t" [ edit 0 5; edit 3 8 ]));
      test "v rejects overlap hidden behind an interleaved empty edit"
        (fun () ->
          (* Sorted order puts [5;5) between [0;10) and [6;8); a naive
             adjacent-pair check would miss the outer overlap. *)
          raises_match (Exn.invalid_arg ~substring:"overlap") (fun () ->
              Fix.v ~title:"t" [ edit 0 10; edit ~text:"" 5 5; edit 6 8 ]));
      test "v rejects an insertion strictly inside a replaced range" (fun () ->
          (* The conflict relation the applier's plan enforces — accepted
             here, the fix would die at apply time as a fixer bug instead
             of failing at construction where the programmer error is. *)
          raises_match (Exn.invalid_arg ~substring:"conflicting") (fun () ->
              Fix.v ~title:"t" [ edit 0 10; edit ~text:"i" 5 5 ]));
      test "v accepts adjacent edits — half-open spans do not overlap"
        (fun () ->
          equal (list span_t)
            [ Span.v ~start:0 ~stop:3; Span.v ~start:3 ~stop:6 ]
            (spans (Fix.v ~title:"t" [ edit 0 3; edit 3 6 ])));
      test "v accepts two insertions at the same point" (fun () ->
          equal int 2
            (List.length
               (Fix.edits
                  (Fix.v ~title:"t" [ edit ~text:"a" 4 4; edit ~text:"b" 4 4 ]))));
      test "v sorts edits by span" (fun () ->
          equal (list span_t)
            [ Span.v ~start:1 ~stop:2; Span.v ~start:5 ~stop:9 ]
            (spans (Fix.v ~title:"t" [ edit 5 9; edit 1 2 ])));
      test "v defaults to Unsafe — safety is earned" (fun () ->
          is_true
            (Fix.applicability (Fix.v ~title:"t" [ edit 0 1 ]) = Fix.Unsafe));
      test "v records the title" (fun () ->
          equal string "compare with []"
            (Fix.title (Fix.v ~title:"compare with []" [ edit 0 1 ])));
    ]

let constructors =
  group "location constructors"
    [
      test "safe_replace is Safe with the location's span" (fun () ->
          let f = Fix.safe_replace (loc 3 9) "text" ~title:"t" in
          is_true (Fix.applicability f = Fix.Safe);
          equal (list span_t) [ Span.v ~start:3 ~stop:9 ] (spans f);
          equal (list string) [ "text" ]
            (List.map (fun (e : Fix.edit) -> e.text) (Fix.edits f)));
      test "safe_delete replaces with the empty string" (fun () ->
          let f = Fix.safe_delete (loc 3 9) ~title:"t" in
          equal (list string) [ "" ]
            (List.map (fun (e : Fix.edit) -> e.text) (Fix.edits f)));
      test "unsafe_replace is Unsafe" (fun () ->
          is_true
            (Fix.applicability (Fix.unsafe_replace (loc 0 1) "x" ~title:"t")
            = Fix.Unsafe));
      test "safe_replace raises on dummy positions" (fun () ->
          (* [Location.none] carries pos_cnum = -1: a rule fix built on a
             PPX-synthesized node is a rule failure, not a wrong edit. *)
          raises_match (Exn.invalid_arg ~substring:"negative") (fun () ->
              Fix.safe_replace Location.none "x" ~title:"t"));
      test "a zero-width location is an insertion point" (fun () ->
          let f = Fix.safe_replace (loc 7 7) "\n" ~title:"t" in
          is_true (Span.is_empty (List.hd (spans f))));
    ]

let updating =
  group "updating"
    [
      test "with_applicability is the engine's downgrade hook" (fun () ->
          let f = Fix.safe_replace (loc 0 1) "x" ~title:"t" in
          is_true
            (Fix.applicability (Fix.with_applicability Fix.Display f)
            = Fix.Display);
          is_true (Fix.applicability f = Fix.Safe));
    ]

let () = Windtrap.run "litany_fix" [ construction; constructors; updating ]
