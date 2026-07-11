(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"unsafe-partial-stdlib" ~group:Rule.Restriction ~since:"1.0"
    ~fix:Rule.Never ~summary:"reference to a partial stdlib eliminator"
    ~doc:
      {|The stdlib's partial eliminators raise on the case their type admits
but their contract excludes: `List.hd` and `List.tl` raise `Failure` on
`[]`, `List.nth` raises on short lists and negative indices, `Option.get`
raises `Invalid_argument` on `None`, and `Result.get_ok`/`get_error`
raise on the other constructor. Each has a total spelling — a match,
`List.nth_opt`, `Option.value`, or `Result.get_ok'` with its carried
message.

    (* bad *)  Option.get (find_user id)
    (* good *) match find_user id with Some u -> … | None -> …

Why restrict this? Partiality is a legitimate tool — a raise in a
failing test is the test doing its job, and field review measured
exactly that population (261 findings on one real workspace, 246 of
them in test code, the sampled remainder contract-true). A partial
eliminator is a finding only where the house has banned the idiom in
favor of total spellings, so the rule is house policy in the
`restriction` tier — off even under `--select all`, cherry-picked by
exact name, with `[@litany.expect]` as the per-call justification
trail.

Fires once per reference that resolves to a listed `Stdlib` declaration
— saturated calls, partial applications, and first-class uses alike, and
through aliases and `open`. Shadowed modules, values merely named `hd`,
the `_opt`/`value` siblings, and the `Not_found` retrieval protocol
(`List.find`, `Hashtbl.find`, `Sys.getenv`, …) deliberately do not fire.
No fix: each remedy restructures control flow.|}
    ()

(* One pattern and one remedy-naming message per listed declaration;
   reference-level matching is the outdated-str-module mechanism. *)
let table =
  List.map
    (fun (name, message) -> (Pat.ident name, message))
    [
      ("Stdlib.List.hd", "List.hd raises on []; match on the list");
      ("Stdlib.List.tl", "List.tl raises on []; match on the list");
      ( "Stdlib.List.nth",
        "List.nth raises on short lists and negative indices; use List.nth_opt"
      );
      ( "Stdlib.Option.get",
        "Option.get raises on None; match or use Option.value" );
      ( "Stdlib.Result.get_ok",
        "Result.get_ok raises on Error; match or use Result.get_ok'" );
      ( "Stdlib.Result.get_error",
        "Result.get_error raises on Ok; match on the result" );
    ]

let rule =
  Rule.expr meta @@ fun u e ->
  let rec first = function
    | [] -> []
    | (p, message) :: rest -> (
        match Pat.run p u e () with
        | Some () -> [ Finding.v ~loc:e.exp_loc message ]
        | None -> first rest)
  in
  first table
