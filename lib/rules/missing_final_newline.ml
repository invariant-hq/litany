(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"missing-final-newline" ~group:Rule.Style
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Always
    ~summary:"file does not end with a newline"
    ~doc:
      {|A file whose last line has no terminating LF confuses line-oriented
tools — `cat` runs files together, `wc -l` miscounts, diffs grow the
"no newline at end of file" wart — and appending a line churns the
previous one.

    (* bad *)  …let x = 1⏹
    (* good *) …let x = 1␊⏹

Reports a zero-width finding at the end-of-file insertion point when the
last byte of a non-empty file is not LF. Empty files are clean, and CRLF
endings are accepted because their final byte is LF. Every finding carries
the insertion fix (`add a final newline`), appending one line terminator
in the file's own style: `\r\n` when the file's last line break is CRLF,
one LF otherwise — a fix must not leave a file with mixed endings.|}
    ()

let rule =
  Rule.source meta @@ fun src ->
  let len = Source.length src in
  if len = 0 then []
  else if Char.equal (Source.contents src).[len - 1] '\n' then []
  else
    match Source.location src (Span.v ~start:len ~stop:len) with
    | None -> []
    | Some loc ->
        (* Match the file's own ending style: a bare LF appended to a
           CRLF file leaves it inconsistent with itself. *)
        let text =
          let contents = Source.contents src in
          match String.rindex_opt contents '\n' with
          | Some i when i > 0 && Char.equal contents.[i - 1] '\r' -> "\r\n"
          | Some _ | None -> "\n"
        in
        let fix = Fix.safe_replace loc text ~title:"add a final newline" in
        [ Finding.v ~fix ~loc "file does not end with LF" ]
