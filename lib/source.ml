(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* [line_starts c] is the byte offset at which each line of [c] starts, in
   order. A line starts at offset 0 and after every LF except one ending the
   bytes — a trailing LF closes the last line, it opens no new one. *)
let line_starts contents =
  let len = String.length contents in
  if len = 0 then [||]
  else begin
    let count = ref 1 in
    for i = 0 to len - 2 do
      if contents.[i] = '\n' then incr count
    done;
    let starts = Array.make !count 0 in
    let next = ref 1 in
    for i = 0 to len - 2 do
      if contents.[i] = '\n' then begin
        starts.(!next) <- i + 1;
        incr next
      end
    done;
    starts
  end

type t = { path : string; contents : string; index : int array Lazy.t }

let v ~path contents = { path; contents; index = lazy (line_starts contents) }
let path s = s.path
let contents s = s.contents
let length s = String.length s.contents
let lines s = Array.length (Lazy.force s.index)

let slice s sp =
  if Span.stop sp > length s then None
  else Some (String.sub s.contents (Span.start sp) (Span.length sp))

(* [line_stop s starts n] is the stop offset of line [n], LF excluded. The
   1-based [n] must be in [[1;Array.length starts]]. *)
let line_stop s starts n =
  if n < Array.length starts then starts.(n) - 1
  else
    let len = length s in
    if len > 0 && s.contents.[len - 1] = '\n' then len - 1 else len

let line s n =
  let starts = Lazy.force s.index in
  if n < 1 || n > Array.length starts then None
  else Some (Span.v ~start:starts.(n - 1) ~stop:(line_stop s starts n))

(* Greatest [i] with [starts.(i) <= off]. Requires [starts] non-empty and
   [off >= 0]; [starts.(0) = 0] makes the invariant [starts.(lo) <= off]
   hold from the start. *)
let line_of_offset starts off =
  let lo = ref 0 and hi = ref (Array.length starts - 1) in
  while !lo < !hi do
    let mid = (!lo + !hi + 1) / 2 in
    if starts.(mid) <= off then lo := mid else hi := mid - 1
  done;
  !lo

let position s off =
  if off < 0 || off > length s then None
  else
    let starts = Lazy.force s.index in
    let pos_lnum, pos_bol =
      if Array.length starts = 0 then (1, 0)
      else
        let i = line_of_offset starts off in
        (i + 1, starts.(i))
    in
    Some { Lexing.pos_fname = s.path; pos_lnum; pos_bol; pos_cnum = off }

let location s sp =
  match (position s (Span.start sp), position s (Span.stop sp)) with
  | Some loc_start, Some loc_end ->
      Some { Location.loc_start; loc_end; loc_ghost = false }
  | _ -> None

let consistent s (pos : Lexing.position) =
  let starts = Lazy.force s.index in
  let count = Array.length starts in
  let n = pos.pos_lnum in
  1 <= n && n <= count
  && pos.pos_bol = starts.(n - 1)
  &&
  (* Line stop including the LF: the next line's start, or the end of the
     bytes for the last line. *)
  let stop = if n < count then starts.(n) else length s in
  pos.pos_bol <= pos.pos_cnum && pos.pos_cnum <= stop
