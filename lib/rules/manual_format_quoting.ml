(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-format-quoting" ~group:Rule.Pedantic
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Sometimes
    ~summary:"format literal hand-quotes %s where %S quotes and escapes"
    ~doc:
      {|A format string that hand-writes quotes around `%s` — `"name=\"%s\""`
— re-implements `%S` minus its escaping: `%S` prints the argument quoted
*and* OCaml-escaped, so payloads containing quotes, backslashes, or
control characters stay unambiguous.

    (* bad *)  Printf.sprintf "name=\"%s\"" n
    (* good *) Printf.sprintf "name=%S" n

Fires once per typed format literal containing the byte sequence
`"` `%` `s` `"`, whatever function consumes it — `Printf`, `Format`, and
every user of `format6` alike. Plain strings that merely contain the
sequence are never elaborated to a format constructor and are clean by
construction; dynamic formats have no literal. The fix replaces each
hand-quoted `%s` with `%S` and is Unsafe: `%S` escapes its argument
where the hand-written quotes do not, which changes output on payloads
containing quotes, backslashes, or control characters — usually the
improvement the author wants, but a behavior change.|}
    ()

let message = "hand-quoted %s re-implements %S without its escaping"

(* The post-lexing bytes the [format] view captures: fire on the 4-byte
   sequence quote-percent-s-quote. *)
let quoted_s = "\"%s\""

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec at i =
    i + m <= n && (String.equal (String.sub s i m) sub || at (i + 1))
  in
  at 0

(* The fix edits the source literal, where the hand-written quotes appear
   escaped: the 6 source bytes backslash-quote-percent-s-backslash-quote.
   Only a plain double-quoted literal is rewritten — a quoted-string
   literal or an escape spelled another way ships without the fix. *)
let source_quoted_s = "\\\"%s\\\""

let replace_all s ~sub ~by =
  let b = Buffer.create (String.length s) in
  let n = String.length s and m = String.length sub in
  let rec go i changed =
    if i >= n then changed
    else if i + m <= n && String.equal (String.sub s i m) sub then (
      Buffer.add_string b by;
      go (i + m) true)
    else (
      Buffer.add_char b s.[i];
      go (i + 1) changed)
  in
  if go 0 false then Some (Buffer.contents b) else None

(* The literal's own source bytes — [Unit.splice]'s guards without its
   parenthesization, which would wrap any literal containing quotes. *)
let literal_slice u (e : Typedtree.expression) =
  if Unit.preprocessed u then None
  else
    let loc = e.exp_loc in
    let src = Unit.source u in
    if
      (not loc.Location.loc_ghost)
      && Source.consistent src loc.Location.loc_start
      && Source.consistent src loc.Location.loc_end
      && loc.Location.loc_start.Lexing.pos_cnum
         <= loc.Location.loc_end.Lexing.pos_cnum
    then Source.slice src (Span.of_location loc)
    else None

let build_fix u e =
  match literal_slice u e with
  | Some text
    when String.length text >= 2
         && text.[0] = '"'
         && text.[String.length text - 1] = '"' ->
      Option.map
        (fun fixed ->
          Fix.unsafe_replace e.exp_loc fixed
            ~title:"use %S (also escapes the argument)")
        (replace_all text ~sub:source_quoted_s ~by:"%S")
  | Some _ | None -> None

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run Pat.format u e Fun.id with
  | Some bytes when contains bytes quoted_s ->
      let fix = build_fix u e in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
  | Some _ | None -> []
