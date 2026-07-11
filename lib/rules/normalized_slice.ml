(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

(* Normalized source-slice equality — the shared technique:
   every maximal run of space/tab/CR/LF collapses to one space, leading
   and trailing runs drop, and nothing else is touched — no comment
   stripping, no token-level normalization. Every report built on this
   equality means "the author wrote the same bytes twice". *)
let normalize s =
  let b = Buffer.create (String.length s) in
  let ws c = c = ' ' || c = '\t' || c = '\n' || c = '\r' in
  let pending = ref false in
  String.iter
    (fun c ->
      if ws c then pending := Buffer.length b > 0
      else begin
        if !pending then Buffer.add_char b ' ';
        pending := false;
        Buffer.add_char b c
      end)
    s;
  Buffer.contents b

let slice u (loc : Location.t) =
  if loc.Location.loc_ghost then None
  else Source.slice (Unit.source u) (Span.of_location loc)
