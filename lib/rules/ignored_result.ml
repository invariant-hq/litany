(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"ignored-result" ~group:Rule.Restriction ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"result or option value is discarded by a wildcard binding"
    ~doc:
      {|A `result` or `option` is a value whose type asks the reader to
examine it: an error or an absence is part of the answer. Binding it to
`_` silences that question wholesale, where handling — or a deliberate
`ignore` naming the intent — keeps it visible.

    (* bad *)  let _ = write_file path contents in …
    (* good *) match write_file path contents with
               | Ok () -> …
               | Error e -> log e

Why restrict this? Discarding a result is sometimes exactly the point —
field review found every sampled finding intentional (a discarded
retry result whose side effects were the test). "Never discard a
result through `_`" is a discipline a codebase adopts, not a defect the
catalog can claim universally. So the rule is
`restriction`-tier house policy: off even under `--select all`,
cherry-picked by exact name, with a deliberate `ignore` (or a named
binding) as the compliant spelling where discarding is meant.

Fires on a wildcard binding (`let _ = e`, at any depth) whose bound
expression's head type constructor is canonically `Stdlib.result` or
`Stdlib.option`. The head is compared as inferred: an abbreviation such
as `type t = int option` stays clean, as do same-spelling `result` or
`option` types declared elsewhere. Named bindings (`let _x = …` included),
unit and every other head type, `ignore e` (an application, not a
binding), and the discard positions compiler warning 10 already owns —
structure items, sequence left-hand sides, loop bodies — deliberately do
not fire. Replacing the wildcard means deciding how to handle the value,
so there is no fix.|}
    ()

let result_or_option = Pat.(typ "Stdlib.result" ||| typ "Stdlib.option")

let rule =
  Rule.binding meta @@ fun u vb ->
  match vb.Typedtree.vb_pat.pat_desc with
  | Typedtree.Tpat_any -> (
      match Pat.run result_or_option u vb.vb_expr.exp_type true with
      | Some true ->
          [
            Finding.v ~loc:vb.vb_loc
              "result or option value is discarded by a wildcard binding";
          ]
      | Some false | None -> [])
  | _ -> []
