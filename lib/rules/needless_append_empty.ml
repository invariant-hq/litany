(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-append-empty" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"append or concatenation with the neutral element"
    ~doc:
      {|Appending the neutral element does nothing — except allocate.
`[] @ l` is `l` itself (the stdlib's append returns its second argument
on an empty first); `l @ []` walks and copies `l` to end where it
started; `"" ^ s` and `s ^ ""` allocate a fresh copy of `s` (`^` never
returns an operand).

    (* bad *)  xs @ []
    (* good *) xs

Fires when `@` or `List.append` resolves to its `Stdlib` declaration
with the predefined `[]` as either operand, and when `^` or
`String.cat` does with the literal `""` as either operand; a both-empty
operation reports once. Singleton appends (`[x] @ l`), shadowed
operators, `String.concat`, and `Bytes.cat` deliberately do not fire.
The fix replaces the whole application with the other operand: safe for
`[] @ l` (result, effects, and physical identity all preserved), unsafe
for the other three legs — they remove a copy, and legacy code copies
strings via `s ^ ""` deliberately.|}
    ()

let list_message = "appending the empty list is redundant"
let string_message = "concatenating the empty string is redundant"
let lists = Pat.idents [ "Stdlib.(@)"; "Stdlib.List.append" ]
let strings = Pat.idents [ "Stdlib.(^)"; "Stdlib.String.cat" ]

(* The four legs. Left-empty legs run first, so a both-empty operation
   ([[] @ []], ["" ^ ""]) reports once, as its left-empty leg. *)
let list_left = Pat.(apply lists (enil ^:: __ ^:: nil))
let list_right = Pat.(apply lists (__ ^:: enil ^:: nil))
let string_left = Pat.(apply strings (estring (cst "") ^:: __ ^:: nil))
let string_right = Pat.(apply strings (__ ^:: estring (cst "") ^:: nil))

let unsafe_list_title =
  "drop the append — removes a list copy (physical identity changes)"

let unsafe_string_title =
  "drop the concatenation — removes a string copy (physical identity changes)"

let rule =
  Rule.expr meta @@ fun u e ->
  let finding message fix_of_src other =
    let fix = Option.map fix_of_src (Unit.splice u other) in
    [ Finding.v ?fix ~loc:e.exp_loc message ]
  in
  match Pat.run list_left u e Fun.id with
  | Some other ->
      (* stdlib append returns its second argument on an empty first:
         result, effects, and physical identity are all preserved. *)
      finding list_message
        (fun src -> Fix.safe_replace e.exp_loc src ~title:"drop the append")
        other
  | None -> (
      match Pat.run list_right u e Fun.id with
      | Some other ->
          finding list_message
            (fun src ->
              Fix.unsafe_replace e.exp_loc src ~title:unsafe_list_title)
            other
      | None -> (
          match Pat.run string_left u e Fun.id with
          | Some other ->
              finding string_message
                (fun src ->
                  Fix.unsafe_replace e.exp_loc src ~title:unsafe_string_title)
                other
          | None -> (
              match Pat.run string_right u e Fun.id with
              | Some other ->
                  finding string_message
                    (fun src ->
                      Fix.unsafe_replace e.exp_loc src
                        ~title:unsafe_string_title)
                    other
              | None -> [])))
