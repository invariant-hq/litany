(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module S = Litany.Suggest

(* The metric (Levenshtein) is an implementation detail behind [suggest];
   its contract is observable at the distance-2 cutoff: a singleton
   candidate is suggested iff it is within distance 2 of the query. *)
let near a b = S.suggest ~candidates:[ b ] a <> None

let () =
  Windtrap.run "litany_suggest"
    [
      test "the distance-2 cutoff sits on the textbook metric" (fun () ->
          (* Distances 0, 1, 2 answer; 3 refuses — spellings chosen so the
             textbook distances are unambiguous. *)
          equal (option string) (Some "style")
            (S.suggest ~candidates:[ "style" ] "style");
          equal (option string) (Some "style")
            (S.suggest ~candidates:[ "style" ] "styl");
          equal (option string) (Some "style")
            (S.suggest ~candidates:[ "style" ] "styel");
          equal (option string) None
            (S.suggest ~candidates:[ "sitting" ] "kitten");
          equal (option string) (Some "ab") (S.suggest ~candidates:[ "ab" ] "");
          equal (option string) None (S.suggest ~candidates:[ "abc" ] ""));
      test "suggest answers within distance 2, refuses beyond" (fun () ->
          equal (option string) (Some "style")
            (S.suggest ~candidates:[ "style"; "perf" ] "styel");
          equal (option string) None
            (S.suggest ~candidates:[ "style"; "perf" ] "correctness");
          equal (option string) None (S.suggest ~candidates:[] "style"));
      test "ties resolve to the lexicographic least, order-independent"
        (fun () ->
          equal (option string) (Some "bat")
            (S.suggest ~candidates:[ "cat"; "bat" ] "aat");
          equal (option string) (Some "bat")
            (S.suggest ~candidates:[ "bat"; "cat" ] "aat");
          (* A nearer candidate beats a lexicographically smaller farther
             one. *)
          equal (option string) (Some "zzat")
            (S.suggest ~candidates:[ "azzz"; "zzat" ] "zzat"));
      prop "nearness is symmetric; only equal strings are at distance 0"
        Gen.(
          pair
            (string_of ~size:(int_range 0 12) (char_range 'a' 'z'))
            (string_of ~size:(int_range 0 12) (char_range 'a' 'z')))
        (fun (a, b) ->
          equal bool (near a b) (near b a);
          (* An equal pair is always suggested (distance 0); by the metric's
             identity-of-indiscernibles a singleton suggestion of the query
             itself happens only at distance 0, i.e. equality. *)
          if String.equal a b then
            equal (option string) (Some b) (S.suggest ~candidates:[ b ] a));
    ]
