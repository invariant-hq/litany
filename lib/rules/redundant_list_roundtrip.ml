(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-list-roundtrip" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Never ~summary:"list converted to a sequence and immediately back"
    ~doc:
      {|`List.of_seq (List.to_seq xs)` walks the list twice and allocates a
fresh copy just to end where it started.

    (* bad *)  List.of_seq (List.to_seq xs)
    (* good *) xs

Fires only when both conversions resolve to their `Stdlib.List`
declarations and the inner application feeds the outer one directly; the
types then already prove the roundtrip. The compiler collapses `|>` into
direct applications, so `xs |> List.to_seq |> List.of_seq` fires too.
Shadowed or let-rebound names, sequence work between the conversions,
the reverse `to_seq (of_seq s)` direction, and other `of_seq` targets
(`Array.of_seq`) deliberately do not fire. No fix: `List.of_seq`
allocates a fresh list, so removing the roundtrip changes physical
identity.|}
    ()

let roundtrip =
  Pat.(
    apply
      (ident "Stdlib.List.of_seq")
      (apply (ident "Stdlib.List.to_seq") (drop ^:: nil) ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run roundtrip u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "list-to-sequence conversion followed by List.of_seq is redundant";
      ]
