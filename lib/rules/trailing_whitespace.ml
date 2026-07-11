(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"trailing-whitespace" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Always ~summary:"trailing spaces or tabs at end of line"
    ~doc:
      {|Trailing whitespace is invisible, churns diffs, and survives only
until the next editor with different settings touches the line.

    (* bad *)  let x = 1␣␣
    (* good *) let x = 1

Reports each maximal run of ASCII space or tab immediately before LF,
CRLF, or end of file. A lone CR is ordinary source content, not a line
ending, so whitespace before one deliberately does not fire. Every finding
carries the deletion fix (`delete the trailing whitespace`), removing
exactly the reported run.|}
    ()

let rule =
  Rule.source meta @@ fun src ->
  let text = Source.contents src in
  let len = String.length text in
  let findings = ref [] in
  let start = ref (-1) in
  let report stop =
    if !start >= 0 then
      match Source.location src (Span.v ~start:!start ~stop) with
      | Some loc ->
          let fix =
            Fix.safe_delete loc ~title:"delete the trailing whitespace"
          in
          findings := Finding.v ~fix ~loc "trailing whitespace" :: !findings
      | None -> ()
  in
  for i = 0 to len - 1 do
    match text.[i] with
    | ' ' | '\t' -> if !start < 0 then start := i
    | '\r' when i + 1 < len && text.[i + 1] = '\n' ->
        (* CRLF: the run ends before the CR; the LF arm reports it. *)
        ()
    | '\n' ->
        report (if i > 0 && text.[i - 1] = '\r' then i - 1 else i);
        start := -1
    | _ -> start := -1
  done;
  report len;
  List.rev !findings
