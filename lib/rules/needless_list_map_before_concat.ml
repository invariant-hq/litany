(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"needless-list-map-before-concat" ~group:Rule.Perf
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"List.map feeding concatenation builds an intermediate list"
    ~doc:
      {|`List.concat (List.map f xs)` builds a complete intermediate list of
lists only for the concatenation to traverse and discard it;
`List.concat_map f xs` fuses the two passes.

    (* bad *)  List.concat (List.map f xs)
    (* good *) List.concat_map f xs

Fires only when the concatenation (`List.concat` or `List.flatten`) and
`List.map` resolve to their `Stdlib` declarations and the two-argument
map application feeds the concatenation directly — including
`List.map f xs |> List.concat`, which the compiler collapses into that
shape. Shadowed or let-rebound names, `List.concat_map` itself, partial
applications (`xs |> List.map f |> List.concat` leaves one), and
anything between the map and the concatenation deliberately do not fire.
No automatic fix in this release — the promise flips to `Sometimes` when
the `List.concat_map` fix lands.

Stable on field evidence: all 27 reviewed sightings were literally the
bad shape, unambiguous and
mechanical — the cleanest graduation case in the catalog.|}
    ()

let shape =
  Pat.(
    apply
      (idents [ "Stdlib.List.concat"; "Stdlib.List.flatten" ])
      (apply (ident "Stdlib.List.map") (drop ^:: drop ^:: nil) ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run shape u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "List.map immediately before list concatenation creates an \
           intermediate list";
      ]
