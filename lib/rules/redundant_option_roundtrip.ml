(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-option-roundtrip" ~group:Rule.Perf ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"option converted to a list only to take its head back"
    ~doc:
      {|`List.nth_opt (Option.to_list o) 0` allocates an intermediate list
just to rebuild the option it started from — the whole expression is `o`.

    (* bad *)  List.nth_opt (Option.to_list o) 0
    (* good *) o

Fires only when both functions resolve to their `Stdlib` declarations and
the index is the integer literal `0`; the types then already prove the
roundtrip. Shadowed or let-rebound names, any other index (literal or
not), partial applications, operator pipelines, and anything between the
two conversions deliberately do not fire. No fix: replacing the
expression with `o` changes physical identity, which a caller may
observe.|}
    ()

let roundtrip =
  Pat.(
    apply
      (ident "Stdlib.List.nth_opt")
      (apply (ident "Stdlib.Option.to_list") (drop ^:: nil)
      ^:: eint (cst 0)
      ^:: nil))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run roundtrip u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "option-to-list conversion followed by List.nth_opt is redundant";
      ]
