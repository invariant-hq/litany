(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"unsafe-obj-magic" ~group:Rule.Restriction ~since:"1.0"
    ~fix:Rule.Never ~summary:"use of Obj.magic"
    ~doc:
      {|`Obj.magic` bypasses the type system entirely: the checker accepts
any use at any type, and a mistake becomes memory corruption at run time,
not a compile error.

    (* bad *)  let id : 'a -> 'a = Obj.magic
    (* good *) a typed interface, a GADT, or a documented unsafe module
               boundary reviewed on its own

Why restrict this? Every real use is a deliberate kernel: the population
is specialist code where each use was justified and reviewed on its own —
corpus review found no `Obj.magic` kernels in application code at all.
"No `Obj.magic`" is a house ban a workspace
adopts, not a universal improvement the catalog can claim. So the rule is
`restriction`-tier policy: off even under `--select all`, cherry-picked by
exact name, with the reviewed boundary carrying its `[@litany.allow]`
justification.

Fires at every identifier expression whose resolved identity is
`Stdlib.Obj.magic` — direct calls, opened uses, and first-class references
alike, at the identifier itself. Shadowed same-spelling definitions, later
uses of a value bound to `Obj.magic` (the binding's right-hand side already
fired), other `Obj` members, and unresolved identities deliberately do not
fire. There is no automatic fix.|}
    ()

let magic = Pat.ident "Stdlib.Obj.magic"

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run magic u e () with
  | Some () -> [ Finding.v ~loc:e.exp_loc "Obj.magic bypasses the type system" ]
  | None -> []
