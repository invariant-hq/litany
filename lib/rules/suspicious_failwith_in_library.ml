(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-failwith-in-library" ~group:Rule.Restriction
    ~since:"1.0" ~fix:Rule.Never ~summary:"failwith referenced in library code"
    ~doc:
      {|`Failure` is anonymous — the one exception no caller can match
meaningfully — and `failwith` in a library manufactures it at the API
boundary: configuration failures, invariant violations, and stubs all
escape as the same unmatchable exception.

    (* bad *)  let connect cfg = if bad cfg then failwith "bad TLS config" else …
    (* good *) let connect cfg = if bad cfg then Error `Tls_config else Ok …

Why restrict this? The defect is the *escape* — an anonymous `Failure`
crossing the API boundary — and this rule cannot prove an escape: local
failwith trampolines (raise here, catch just above) are a legitimate
style established libraries practice, and the same reference-level
check would flag them. A rule that cannot prove the defect and flags
the practice is house policy by definition, so it sits in the
`restriction` tier: off even under `--select all`, cherry-picked by a
workspace whose libraries speak typed errors, with `[@litany.expect]`
as the justification trail for the trampolines it cannot see.

Fires once per resolved reference to `Stdlib.failwith` — aliasing a
failwith is a failwith — in units whose roster kind is `Library`,
except references lexically enclosed in a `Texp_try` (the same-function
trampoline shape: raise here, catch just above). Executables and tests
fail fast by right and are clean by kind; a unit whose roster carries
no kind is deliberately silent — a metadata-gated rule degrades to
silence, never to guessing. A locally shadowed `failwith` resolves to a
local declaration and never fires. The exemption is meant for a try
whose handler matches `Stdlib.Failure` alone; handler
exception-constructor identity needs a pattern-side view that has not
landed, so any enclosing try exempts — a recorded false negative in
the safe direction. Cross-function trampolines take one `[@litany.expect]`. No
fix: the replacement error path is a design decision.|}
    ~kind_gated:true ()

let message = "failwith in library code raises the anonymous Failure"
let failwith_ref = Pat.(ident "Stdlib.failwith")

(* Enclosure walk: is [target] (by physical identity — the unit caches
   one decoded tree, so the dispatched node is a node of it) inside any
   [Texp_try] of the implementation? The exemption is meant for tries
   whose handler matches [Stdlib.Failure] alone; without a pattern-side
   exception-constructor view every try exempts (recorded FN). *)
let enclosed_in_try (root : Typedtree.structure) (target : Typedtree.expression)
    =
  let exempt = ref false and depth = ref 0 in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub (x : Typedtree.expression) ->
          if x == target && !depth > 0 then exempt := true;
          if not !exempt then
            match x.exp_desc with
            | Typedtree.Texp_try _ ->
                incr depth;
                default.expr sub x;
                decr depth
            | _ -> default.expr sub x);
    }
  in
  iterator.structure iterator root;
  !exempt

let rule =
  Rule.expr meta @@ fun u e ->
  match Unit.kind u with
  | Some Unit.Library -> (
      (* Constructor-head gate: only identifier references can match,
         and the whole-unit enclosure walk runs only at actual failwith
         references — the walk visits every node, so the miss path must
         stay cheap. *)
      match e.exp_desc with
      | Typedtree.Texp_ident _ -> (
          match Pat.run failwith_ref u e () with
          | Some () when not (enclosed_in_try (Unit.implementation u) e) ->
              [ Finding.v ~loc:e.exp_loc message ]
          | Some () | None -> [])
      | _ -> [])
  | Some Unit.Executable | Some Unit.Test | None -> []
