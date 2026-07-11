(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"invalid-hashtable-key" ~group:Rule.Suspicious ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"polymorphic Hashtbl operation on a value proved functional"
    ~doc:
      {|`Stdlib.Hashtbl`'s default operations hash and compare keys with the
polymorphic primitives. A functional key is broken at runtime, but not
by hashing: hashing a closure returns a value — different on every run
— and a lookup raises `Invalid_argument` only when a distinct
functional key shares its bucket, misses silently otherwise, and
succeeds only on physical identity.

    (* bad *)  Hashtbl.mem callbacks handler
    (* good *) Hashtbl.mem callbacks (Handler.id handler)

Fires when `Hashtbl.find`, `find_opt`, `find_all`, `mem`, `remove`,
`seeded_hash`, `hash`, `hash_param`, `add`, or `replace` resolves to its
`Stdlib` declaration at exact arity and the hashed argument's type
proves a function: an arrow, or a `list`, `array`, or `option` of one. The proof never guesses — type
variables and abbreviations (`type callback = int -> int`) stay clean,
as do shadowed `Hashtbl` modules, partial applications, and
`Hashtbl.Make` instances, whose operations carry the functor's own
identities and whose custom hash is exactly the remedy. No fix: choosing
a hashable key needs domain intent.|}
    ()

(* Tuple components still await a version-stable Ttuple seam — a
   recorded false negative. *)
let keyed =
  Pat.(
    apply (ident "Stdlib.Hashtbl.hash") (__ ^:: nil)
    ||| apply
          (idents
             [
               "Stdlib.Hashtbl.find";
               "Stdlib.Hashtbl.find_opt";
               "Stdlib.Hashtbl.find_all";
               "Stdlib.Hashtbl.mem";
               "Stdlib.Hashtbl.remove";
               "Stdlib.Hashtbl.seeded_hash";
             ])
          (drop ^:: __ ^:: nil)
    ||| apply
          (idents [ "Stdlib.Hashtbl.add"; "Stdlib.Hashtbl.replace" ])
          (drop ^:: __ ^:: drop ^:: nil)
    ||| apply (ident "Stdlib.Hashtbl.hash_param") (drop ^:: drop ^:: __ ^:: nil))

(* Predefined containers whose elements the polymorphic hash walks. *)
let container_paths = Predef.[ path_list; path_array; path_option ]

(* The proof walks visible structure only: no abbreviation expansion, no
   variable guessing — unknown immediacy stays clean. *)
let rec proves_function ty =
  match Types.get_desc ty with
  | Types.Tarrow _ -> true
  | Types.Tconstr (p, args, _) when List.exists (Path.same p) container_paths ->
      List.exists proves_function args
  | _ -> false

let rule =
  Rule.expr meta @@ fun u e ->
  match
    Pat.run keyed u e (fun (subject : Typedtree.expression) ->
        proves_function subject.exp_type)
  with
  | Some true ->
      [
        Finding.v ~loc:e.exp_loc
          "Hashtbl's polymorphic hash is unreliable on functional values: \
           nondeterministic per run, and lookups miss or raise";
      ]
  | Some false | None -> []
