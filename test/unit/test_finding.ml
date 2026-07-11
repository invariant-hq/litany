(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Finding = Litany.Finding

let pos fname lnum bol cnum =
  { Lexing.pos_fname = fname; pos_lnum = lnum; pos_bol = bol; pos_cnum = cnum }

let loc ?(ghost = false) ?(fname = "a.ml") start stop =
  {
    Location.loc_start = pos fname 1 0 start;
    loc_end = pos fname 1 0 stop;
    loc_ghost = ghost;
  }

let finding_t = Testable.make ~pp:Finding.pp ~equal:Finding.equal

let construction_tests =
  group "construction"
    [
      test "v defaults to no fix" (fun () ->
          let f = Finding.v ~loc:(loc 0 3) "message" in
          equal string "message" (Finding.message f);
          is_none (Finding.fix f));
    ]

let equality_tests =
  group "equality and order"
    [
      test "equal is (location, message)" (fun () ->
          let f = Finding.v ~loc:(loc 0 3) "m" in
          equal finding_t f (Finding.v ~loc:(loc 0 3) "m");
          not_equal finding_t f (Finding.v ~loc:(loc 0 4) "m");
          not_equal finding_t f (Finding.v ~loc:(loc 0 3) "other");
          not_equal finding_t f (Finding.v ~loc:(loc ~ghost:true 0 3) "m"));
      test "compare orders by path, start, end, message" (fun () ->
          let f1 = Finding.v ~loc:(loc ~fname:"a.ml" 5 9) "m" in
          let f2 = Finding.v ~loc:(loc ~fname:"b.ml" 0 1) "m" in
          let f3 = Finding.v ~loc:(loc ~fname:"a.ml" 5 12) "m" in
          let f4 = Finding.v ~loc:(loc ~fname:"a.ml" 5 9) "n" in
          let f5 = Finding.v ~loc:(loc ~fname:"a.ml" 2 3) "m" in
          is_true (Finding.compare f1 f2 < 0);
          is_true (Finding.compare f5 f1 < 0);
          is_true (Finding.compare f1 f3 < 0);
          is_true (Finding.compare f1 f4 < 0);
          equal int 0 (Finding.compare f1 f1));
      test "the order is compatible with equal" (fun () ->
          let f = Finding.v ~loc:(loc 0 3) "m" in
          let f' = Finding.v ~loc:(loc 0 3) "m" in
          is_true (Finding.equal f f');
          equal int 0 (Finding.compare f f'));
      test "pp mentions the location and message" (fun () ->
          let f = Finding.v ~loc:(loc 0 3) "the message" in
          let s = Format.asprintf "%a" Finding.pp f in
          contains ~sub:"a.ml" s;
          contains ~sub:"the message" s);
    ]

let () = run "litany_finding" [ construction_tests; equality_tests ]
