(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-conversion-roundtrip" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Sometimes ~summary:"conversion immediately undone by its inverse"
    ~doc:
      {|Converting a value out of its type and immediately back does
allocation and parsing work to end where it started:
`int_of_string (string_of_int n)` is `n`.

    (* bad *)  int_of_string (string_of_int n)
    (* good *) n

Fires only on compositions proved identities by the stdlib's contracts,
with both conversions resolving to their `Stdlib` declarations and the
inner application feeding the outer directly: `int_of_string` of
`string_of_int`, `bool_of_string` of `string_of_bool`, `Char.chr` of
`Char.code`, `of_string` of `to_string` for `Int32`/`Int64`/`Nativeint`,
and `Bytes.to_string` of `Bytes.of_string`. Pipeline spellings collapse
and fire. The reverse directions deliberately do not: `string_of_int
(int_of_string s)` canonicalizes (`"+3"`, `"0x10"` change),
`Char.code (Char.chr n)` deletes a range check, `Bytes.of_string
(Bytes.to_string b)` must stay a fresh mutable copy, and the lossy float
pair is excluded; shadowed conversions and work between the two also
stay clean. The fix — the inner argument itself — is Safe for the
unboxed pairs (int, bool, char) and withheld for the boxed and copying
pairs, where replacement changes physical identity.|}
    ()

(* Each row is a reviewed identity claim: [outer (inner x)] is [x]. The
   pattern captures [x]; [safe] gates the fix to the unboxed pairs, where
   the roundtrip returns the very value. *)
let table =
  List.map
    (fun (outer, inner, message, safe) ->
      ( Pat.(apply (ident outer) (apply (ident inner) (__ ^:: nil) ^:: nil)),
        message,
        safe ))
    [
      ( "Stdlib.int_of_string",
        "Stdlib.string_of_int",
        "int_of_string undoes string_of_int; use the integer itself",
        true );
      ( "Stdlib.bool_of_string",
        "Stdlib.string_of_bool",
        "bool_of_string undoes string_of_bool; use the boolean itself",
        true );
      ( "Stdlib.Char.chr",
        "Stdlib.Char.code",
        "Char.chr undoes Char.code; use the character itself",
        true );
      ( "Stdlib.Int32.of_string",
        "Stdlib.Int32.to_string",
        "Int32.of_string undoes Int32.to_string; use the value itself",
        false );
      ( "Stdlib.Int64.of_string",
        "Stdlib.Int64.to_string",
        "Int64.of_string undoes Int64.to_string; use the value itself",
        false );
      ( "Stdlib.Nativeint.of_string",
        "Stdlib.Nativeint.to_string",
        "Nativeint.of_string undoes Nativeint.to_string; use the value itself",
        false );
      ( "Stdlib.Bytes.to_string",
        "Stdlib.Bytes.of_string",
        "Bytes.to_string of Bytes.of_string is the string itself, up to \
         physical identity",
        false );
    ]

let rule =
  Rule.expr meta @@ fun u e ->
  let rec first = function
    | [] -> []
    | (p, message, safe) :: rest -> (
        match Pat.run p u e Fun.id with
        | None -> first rest
        | Some x ->
            let fix =
              if safe then
                Option.map
                  (fun src ->
                    Fix.safe_replace e.exp_loc src
                      ~title:"drop the conversion roundtrip")
                  (Unit.splice u x)
              else None
            in
            [ Finding.v ?fix ~loc:e.exp_loc message ])
  in
  first table
