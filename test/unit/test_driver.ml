(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The convergence loop's progress witness (CS-FIX--01): the fingerprint
   over a pass's kept-finding multiset. The [--fix] loop stops honestly
   when a pass reproduces an earlier pass's fingerprint — the applied
   fixes resolved nothing, or antagonistic fixes are undoing each other.
   The oscillation shape itself is not cheaply constructible as a cram
   (no antagonistic fix pair exists in the real catalog), so the check's
   mechanism is pinned here. *)

open Windtrap
module Driver = Litany.Driver
module Finding = Litany.Finding

let pos fname cnum =
  { Lexing.pos_fname = fname; pos_lnum = 1; pos_bol = 0; pos_cnum = cnum }

let loc ?(fname = "a.ml") start stop =
  {
    Location.loc_start = pos fname start;
    loc_end = pos fname stop;
    loc_ghost = false;
  }

let f ?fname ?(rule = "r") ?(msg = "m") start stop =
  (rule, Finding.v ~loc:(loc ?fname start stop) msg)

let fp = Driver.findings_fingerprint

let fingerprint =
  group "findings_fingerprint"
    [
      test "order-independent — a multiset, not a sequence" (fun () ->
          let a = f ~rule:"a" 0 3 and b = f ~rule:"b" 5 9 in
          equal string (fp [ a; b ]) (fp [ b; a ]));
      test "counts duplicates — a multiset, not a set" (fun () ->
          let a = f 0 3 in
          not_equal string (fp [ a ]) (fp [ a; a ]));
      test "empty is stable and distinct from non-empty" (fun () ->
          equal string (fp []) (fp []);
          not_equal string (fp []) (fp [ f 0 3 ]));
      test "sensitive to the rule name" (fun () ->
          not_equal string (fp [ f ~rule:"a" 0 3 ]) (fp [ f ~rule:"b" 0 3 ]));
      test "sensitive to the anchor path" (fun () ->
          not_equal string
            (fp [ f ~fname:"a.ml" 0 3 ])
            (fp [ f ~fname:"b.ml" 0 3 ]));
      test "sensitive to the byte span" (fun () ->
          not_equal string (fp [ f 0 3 ]) (fp [ f 0 4 ]);
          not_equal string (fp [ f 0 3 ]) (fp [ f 1 3 ]));
      test "sensitive to the message" (fun () ->
          not_equal string (fp [ f ~msg:"m" 0 3 ]) (fp [ f ~msg:"n" 0 3 ]));
      test "insensitive to fixes — findings only" (fun () ->
          (* The lint state the planner sees is the finding multiset; a
             fix's presence rides the same finding identity. *)
          let bare = ("r", Finding.v ~loc:(loc 0 3) "m") in
          let fixed =
            ( "r",
              Finding.v
                ~fix:
                  (Litany.Fix.v ~applicability:Litany.Fix.Safe ~title:"t"
                     [
                       {
                         Litany.Fix.span = Litany.Span.v ~start:0 ~stop:3;
                         text = "x";
                       };
                     ])
                ~loc:(loc 0 3) "m" )
          in
          equal string (fp [ bare ]) (fp [ fixed ]));
      test "the oscillation shape: pass 3 repeats pass 1, not pass 2" (fun () ->
          (* Two antagonistic fixes: pass 1 reports A, its fix produces
             the code B reports on, B's fix restores the original — the
             byte-true cycle makes pass 3's findings pass 1's exactly.
             Membership over all earlier fingerprints catches it where a
             previous-pass-only check would not. *)
          let pass1 = [ f ~rule:"a" ~msg:"forward" 0 10 ] in
          let pass2 = [ f ~rule:"b" ~msg:"backward" 0 10 ] in
          let pass3 = [ f ~rule:"a" ~msg:"forward" 0 10 ] in
          let seen = [ (2, fp pass2); (1, fp pass1) ] in
          not_equal string (fp pass2) (fp pass1);
          match
            List.find_opt (fun (_, fp') -> String.equal fp' (fp pass3)) seen
          with
          | Some (m, _) -> equal int 1 m
          | None -> failf "pass 3 did not match pass 1's fingerprint");
      test "the no-progress shape: pass 2 repeats pass 1" (fun () ->
          let pass1 = [ f 0 10; f ~rule:"s" 20 30 ] in
          let pass2 = [ f ~rule:"s" 20 30; f 0 10 ] in
          equal string (fp pass1) (fp pass2));
    ]

let () = Windtrap.run "litany_driver" [ fingerprint ]
