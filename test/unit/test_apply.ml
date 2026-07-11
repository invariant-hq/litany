(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Apply = Litany.Apply
module Fix = Litany.Fix
module Span = Litany.Span

let edit ?(text = "x") start stop = { Fix.span = Span.v ~start ~stop; text }

let cand ?(rule = "r") ?applicability ~title edits =
  { Apply.rule; fix = Fix.v ?applicability ~title edits }

let titles = List.map (fun (c : Apply.candidate) -> Fix.title c.fix)

(* {1 Planning} *)

let planning =
  group "plan"
    [
      test "keeps Safe, excludes Unsafe and Display by default" (fun () ->
          let p =
            Apply.plan
              [
                cand ~applicability:Fix.Safe ~title:"s" [ edit 0 1 ];
                cand ~applicability:Fix.Unsafe ~title:"u" [ edit 2 3 ];
                cand ~applicability:Fix.Display ~title:"d" [ edit 4 5 ];
              ]
          in
          equal (list string) [ "s" ] (titles (Apply.selected p));
          equal (list string) [ "u"; "d" ] (titles (Apply.excluded p));
          equal (list string) [] (titles (Apply.conflicting p)));
      test "unsafe:true admits Unsafe, never Display" (fun () ->
          let p =
            Apply.plan ~unsafe:true
              [
                cand ~applicability:Fix.Unsafe ~title:"u" [ edit 2 3 ];
                cand ~applicability:Fix.Display ~title:"d" [ edit 4 5 ];
              ]
          in
          equal (list string) [ "u" ] (titles (Apply.selected p));
          equal (list string) [ "d" ] (titles (Apply.excluded p)));
      test "orders the selected by span, then rule name" (fun () ->
          let p =
            Apply.plan
              [
                cand ~rule:"zeta" ~applicability:Fix.Safe ~title:"late"
                  [ edit 8 9 ];
                cand ~rule:"zeta" ~applicability:Fix.Safe ~title:"z-first"
                  [ edit 0 1 ];
                cand ~rule:"alpha" ~applicability:Fix.Safe ~title:"a-first"
                  [ edit 0 1 ]
                (* conflicts with z-first: equal span *);
              ]
          in
          equal (list string) [ "a-first"; "late" ] (titles (Apply.selected p));
          equal (list string) [ "z-first" ] (titles (Apply.conflicting p)));
      test "drops the later-by-span loser of an overlap, deterministically"
        (fun () ->
          let p =
            Apply.plan
              [
                cand ~applicability:Fix.Safe ~title:"wide" [ edit 0 10 ];
                cand ~applicability:Fix.Safe ~title:"inner" [ edit 4 6 ];
              ]
          in
          equal (list string) [ "wide" ] (titles (Apply.selected p));
          equal (list string) [ "inner" ] (titles (Apply.conflicting p)));
      test "an insertion strictly inside a replaced range conflicts" (fun () ->
          let p =
            Apply.plan
              [
                cand ~applicability:Fix.Safe ~title:"replace" [ edit 0 10 ];
                cand ~applicability:Fix.Safe ~title:"insert"
                  [ edit ~text:"i" 5 5 ];
              ]
          in
          equal (list string) [ "insert" ] (titles (Apply.conflicting p)));
      test "insertions at a boundary and at the same point do not conflict"
        (fun () ->
          let p =
            Apply.plan
              [
                cand ~applicability:Fix.Safe ~title:"replace" [ edit 0 10 ];
                cand ~applicability:Fix.Safe ~title:"at-stop"
                  [ edit ~text:"i" 10 10 ];
                cand ~applicability:Fix.Safe ~title:"also-at-stop"
                  [ edit ~text:"j" 10 10 ];
              ]
          in
          equal int 3 (List.length (Apply.selected p));
          equal (list string) [] (titles (Apply.conflicting p)));
    ]

(* {1 Patching} *)

let patching =
  group "patch"
    [
      test "replaces, deletes, and inserts in one pass" (fun () ->
          equal string "aXcde!"
            (Apply.patch "abcde"
               [ edit ~text:"X" 1 2; edit ~text:"" 0 0; edit ~text:"!" 5 5 ]));
      test "applies edits given in any order" (fun () ->
          equal string "ZbY"
            (Apply.patch "abc" [ edit ~text:"Y" 2 3; edit ~text:"Z" 0 1 ]));
      test "same-point insertions land in list order" (fun () ->
          equal string "abXYc"
            (Apply.patch "abc" [ edit ~text:"X" 2 2; edit ~text:"Y" 2 2 ]));
      test "rejects an edit past the end" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"exceeds") (fun () ->
              Apply.patch "ab" [ edit ~text:"x" 1 3 ]));
      test "rejects conflicting edits" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"conflict") (fun () ->
              Apply.patch "abcdef" [ edit 0 4; edit 2 5 ]));
      test "empty edit list is the identity" (fun () ->
          equal string "abc" (Apply.patch "abc" []));
    ]

(* {1 Applying (IO)} *)

let with_file contents k =
  let dir = Filename.temp_dir "litany-apply-test" "" in
  let path = Filename.concat dir "target.ml" in
  Out_channel.with_open_bin path (fun oc ->
      Out_channel.output_string oc contents);
  Fun.protect
    ~finally:(fun () ->
      Array.iter (fun n -> Sys.remove (Filename.concat dir n)) (Sys.readdir dir);
      Unix.rmdir dir)
    (fun () -> k ~dir ~path)

let read path = In_channel.with_open_bin path In_channel.input_all
let md5 = Digest.MD5.string

(* [target.ml]'s bytes: replacing [0 = 0] with [true] keeps it parsing;
   replacing it with [(] does not. *)
let source = "let a = 0 = 0\n"
let span_0eq0 = (8, 13)

let replacement text =
  let start, stop = span_0eq0 in
  cand ~applicability:Fix.Safe ~title:"t" [ edit ~text start stop ]

let outcome_name = function
  | Apply.Applied -> "applied"
  | Apply.Nothing_to_apply -> "nothing-to-apply"
  | Apply.Stale -> "stale"
  | Apply.Fixer_bug -> "fixer-bug"
  | Apply.Unverifiable -> "unverifiable"
  | Apply.Io_error _ -> "io-error"

(* {1 Correcting} *)

let correcting =
  group "correct"
    [
      test "a fix whose output equals its input is a fixer bug (CS-FIX--01)"
        (fun () ->
          (* Written unconditionally, a no-op fix would re-produce the same
             finding on every convergence pass — the loop could never
             terminate honestly. *)
          let start, stop = span_0eq0 in
          let identity =
            cand ~applicability:Fix.Safe ~title:"t"
              [ edit ~text:"0 = 0" start stop ]
          in
          match Apply.correct source [ identity ] with
          | Error (`Fixer_bug _) -> ()
          | Ok _ -> failf "expected a fixer bug, got Ok"
          | Error `Unverifiable ->
              failf "expected a fixer bug, got Unverifiable");
      test "an empty selection is Ok and unchanged, never a bug" (fun () ->
          match
            Apply.correct source
              [ cand ~applicability:Fix.Display ~title:"t" [ edit 0 1 ] ]
          with
          | Ok bytes -> equal string source bytes
          | Error _ -> failf "expected Ok on an empty selection");
      test "a changing fix still corrects" (fun () ->
          match Apply.correct source [ replacement "true" ] with
          | Ok bytes -> equal string "let a = true\n" bytes
          | Error _ -> failf "expected Ok");
    ]

let applying =
  group "file"
    [
      test "applies, writes the exact bytes, and leaves no temp file" (fun () ->
          with_file source (fun ~dir ~path ->
              let _, o =
                Apply.file ~path ~baseline:(md5 source) [ replacement "true" ]
              in
              equal string "applied" (outcome_name o);
              equal string "let a = true\n" (read path);
              (* Atomicity's visible residue: the temp file is gone — the
                 rename either happened completely or not at all. *)
              equal (list string) [ "target.ml" ]
                (List.sort String.compare (Array.to_list (Sys.readdir dir)))));
      test "accepts a BLAKE128 baseline — either digest algorithm matches"
        (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let _, o =
                Apply.file ~path
                  ~baseline:(Digest.BLAKE128.string source)
                  [ replacement "true" ]
              in
              equal string "applied" (outcome_name o)));
      test "refuses to write when the digest baseline mismatches" (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let _, o =
                Apply.file ~path ~baseline:(md5 "other bytes")
                  [ replacement "true" ]
              in
              equal string "stale" (outcome_name o);
              equal string source (read path)));
      test
        "verifies before writing — a parse failure is a fixer bug, nothing \
         written" (fun () ->
          with_file source (fun ~dir ~path ->
              let _, o =
                Apply.file ~path ~baseline:(md5 source) [ replacement "(" ]
              in
              equal string "fixer-bug" (outcome_name o);
              equal string source (read path);
              equal (list string) [ "target.ml" ]
                (List.sort String.compare (Array.to_list (Sys.readdir dir)))));
      test "an out-of-bounds edit against verified bytes is a fixer bug"
        (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let far =
                cand ~applicability:Fix.Safe ~title:"t"
                  [ edit ~text:"x" 100 200 ]
              in
              let _, o = Apply.file ~path ~baseline:(md5 source) [ far ] in
              equal string "fixer-bug" (outcome_name o);
              equal string source (read path)));
      test "refuses to write into a source that does not parse" (fun () ->
          let broken = "let a = ( 0 = 0\n" in
          with_file broken (fun ~dir:_ ~path ->
              let start = String.length "let a = ( " in
              let c =
                cand ~applicability:Fix.Safe ~title:"t"
                  [ edit ~text:"true" start (start + 5) ]
              in
              let _, o = Apply.file ~path ~baseline:(md5 broken) [ c ] in
              equal string "unverifiable" (outcome_name o);
              equal string broken (read path)));
      test "an unparsable original is refused even when the patch parses"
        (fun () ->
          (* The patch rewrites the broken
             region into parsing OCaml — exactly a fix that touched bytes
             it does not own. The write gate is the original's parse; the
             patched bytes' own parse must not open it. *)
          let broken = "let a = ( 0 = 0\n" in
          with_file broken (fun ~dir:_ ~path ->
              let c =
                cand ~applicability:Fix.Safe ~title:"t"
                  [ edit ~text:"true" 8 15 ]
              in
              let _, o = Apply.file ~path ~baseline:(md5 broken) [ c ] in
              equal string "unverifiable" (outcome_name o);
              equal string broken (read path)));
      test "a symlinked path is written through, not replaced" (fun () ->
          (* The findings anchor in the file, so the
             write resolves the link and lands in its target — the link
             stays a link and the tree keeps its shape. *)
          with_file source (fun ~dir ~path ->
              let link = Filename.concat dir "link.ml" in
              Unix.symlink "target.ml" link;
              let _, o =
                Apply.file ~path:link ~baseline:(md5 source)
                  [ replacement "true" ]
              in
              equal string "applied" (outcome_name o);
              is_true ~msg:"the link is still a symlink"
                ((Unix.lstat link).Unix.st_kind = Unix.S_LNK);
              equal string "let a = true\n" (read path)));
      test "nothing to apply leaves the file alone" (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let unsafe =
                cand ~applicability:Fix.Unsafe ~title:"t" [ edit 0 1 ]
              in
              let plan, o =
                Apply.file ~path ~baseline:(md5 source) [ unsafe ]
              in
              equal string "nothing-to-apply" (outcome_name o);
              equal int 1 (List.length (Apply.excluded plan));
              equal string source (read path)));
      test "a no-op fix through file is a fixer bug — file untouched" (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let start, stop = span_0eq0 in
              let identity =
                cand ~applicability:Fix.Safe ~title:"t"
                  [ edit ~text:"0 = 0" start stop ]
              in
              let _, o = Apply.file ~path ~baseline:(md5 source) [ identity ] in
              equal string "fixer-bug" (outcome_name o);
              equal string source (read path)));
      test "a missing file is an IO error" (fun () ->
          let _, o =
            Apply.file ~path:"nonexistent-dir/nope.ml" ~baseline:(md5 "")
              [ replacement "true" ]
          in
          equal string "io-error" (outcome_name o));
      test "conflict losers are dropped, winners written" (fun () ->
          with_file source (fun ~dir:_ ~path ->
              let start, stop = span_0eq0 in
              let winner =
                cand ~rule:"a" ~applicability:Fix.Safe ~title:"w"
                  [ edit ~text:"true" start stop ]
              in
              let loser =
                cand ~rule:"b" ~applicability:Fix.Safe ~title:"l"
                  [ edit ~text:"false" start stop ]
              in
              let plan, o =
                Apply.file ~path ~baseline:(md5 source) [ loser; winner ]
              in
              equal string "applied" (outcome_name o);
              equal (list string) [ "w" ] (titles (Apply.selected plan));
              equal (list string) [ "l" ] (titles (Apply.conflicting plan));
              equal string "let a = true\n" (read path)));
    ]

let () =
  Windtrap.run "litany_apply" [ planning; patching; correcting; applying ]
