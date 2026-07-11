(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Span = Litany.Span

let span = Testable.make ~pp:Span.pp ~equal:Span.equal

(* Spans with offsets small enough that arithmetic properties stay honest. *)
let gen_span =
  let open Gen in
  with_pp Span.pp
    (let+ a = int_range 0 200 and+ b = int_range 0 200 in
     Span.v ~start:(min a b) ~stop:(max a b))

let gen_offset = Gen.int_range (-10) 220

let position (loc_start : Lexing.position) (loc_end : Lexing.position) =
  { Location.loc_start; loc_end; loc_ghost = false }

let pos cnum =
  { Lexing.pos_fname = "test.ml"; pos_lnum = 1; pos_bol = 0; pos_cnum = cnum }

let construction =
  group "construction"
    [
      test "v records both offsets" (fun () ->
          let s = Span.v ~start:3 ~stop:7 in
          equal int 3 (Span.start s);
          equal int 7 (Span.stop s));
      test "v accepts the empty span" (fun () ->
          let s = Span.v ~start:5 ~stop:5 in
          is_true (Span.is_empty s);
          equal int 0 (Span.length s));
      test "v rejects a negative start" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"negative start") (fun () ->
              Span.v ~start:(-1) ~stop:3));
      test "v rejects stop before start" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"precedes") (fun () ->
              Span.v ~start:4 ~stop:3));
      prop "length is stop minus start" gen_span (fun s ->
          equal int (Span.stop s - Span.start s) (Span.length s));
      prop "is_empty iff length zero" gen_span (fun s ->
          equal bool (Span.length s = 0) (Span.is_empty s));
    ]

let predicates =
  group "predicates"
    [
      prop "contains matches the half-open definition"
        Gen.(pair gen_span gen_offset)
        (fun (s, i) ->
          equal bool (Span.start s <= i && i < Span.stop s) (Span.contains s i));
      prop "an empty span contains no offset"
        Gen.(pair gen_offset gen_offset)
        (fun (at, i) ->
          let at = abs at in
          is_false (Span.contains (Span.v ~start:at ~stop:at) i));
      prop "includes matches the bounds definition"
        Gen.(pair gen_span gen_span)
        (fun (s, sub) ->
          equal bool
            (Span.start s <= Span.start sub && Span.stop sub <= Span.stop s)
            (Span.includes s sub));
      prop "a span includes itself" gen_span (fun s ->
          is_true (Span.includes s s));
      prop "includes carries every contained offset"
        Gen.(triple gen_span gen_span gen_offset)
        (fun (s, sub, i) ->
          if Span.includes s sub && Span.contains sub i then
            is_true (Span.contains s i));
      prop "overlaps iff some offset is in both"
        Gen.(pair gen_span gen_span)
        (fun (s, s') ->
          let naive = ref false in
          for i = Span.start s to Span.stop s - 1 do
            if Span.contains s' i then naive := true
          done;
          equal bool !naive (Span.overlaps s s'));
      prop "overlaps is symmetric"
        Gen.(pair gen_span gen_span)
        (fun (s, s') -> equal bool (Span.overlaps s s') (Span.overlaps s' s));
      test "empty spans overlap nothing, even inside another span" (fun () ->
          let empty = Span.v ~start:5 ~stop:5 in
          let wide = Span.v ~start:0 ~stop:10 in
          is_false (Span.overlaps empty wide);
          is_false (Span.overlaps wide empty);
          is_false (Span.overlaps empty empty);
          (* Containment still admits the empty span: the two relations
             deliberately differ. *)
          is_true (Span.includes wide empty));
    ]

let converting =
  group "of_location"
    [
      test "reads both pos_cnum offsets" (fun () ->
          let s = Span.of_location (position (pos 3) (pos 9)) in
          equal span (Span.v ~start:3 ~stop:9) s);
      test "ignores loc_ghost" (fun () ->
          let loc =
            { (position (pos 1) (pos 2)) with Location.loc_ghost = true }
          in
          equal span (Span.v ~start:1 ~stop:2) (Span.of_location loc));
      test "rejects dummy positions with pos_cnum = -1" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"negative offset") (fun () ->
              Span.of_location (position (pos (-1)) (pos (-1)))));
      test "rejects an end preceding the start" (fun () ->
          raises_match
            (fun e -> match e with Invalid_argument _ -> true | _ -> false)
            (fun () -> Span.of_location (position (pos 9) (pos 3))));
    ]

let ordering =
  group "ordering"
    [
      prop "compare is compatible with equal"
        Gen.(pair gen_span gen_span)
        (fun (s, s') -> equal bool (Span.equal s s') (Span.compare s s' = 0));
      prop "compare orders by start, then stop"
        Gen.(pair gen_span gen_span)
        (fun (s, s') ->
          let expected =
            match Int.compare (Span.start s) (Span.start s') with
            | 0 -> Int.compare (Span.stop s) (Span.stop s')
            | c -> c
          in
          equal int expected (Span.compare s s'));
      prop "compare is antisymmetric"
        Gen.(pair gen_span gen_span)
        (fun (s, s') -> equal int (Span.compare s s') (-Span.compare s' s));
      test "pp formats as a half-open interval" (fun () ->
          equal string "[3;7)"
            (Format.asprintf "%a" Span.pp (Span.v ~start:3 ~stop:7)));
    ]

let () = run "litany_span" [ construction; predicates; converting; ordering ]
