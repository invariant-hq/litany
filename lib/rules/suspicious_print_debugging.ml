(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-print-debugging" ~group:Rule.Restriction
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"console printing entrypoint referenced in library code"
    ~doc:
      {|Library code that writes to stdout or stderr decides something only
the application may decide: whether, where, and how to print. A stray
`print_endline` in a library is usually a debugging leftover; a
deliberate one is a layering violation that corrupts the hosting
application's own output.

    (* bad *)  let load path = print_endline path; parse path
    (* good *) let load path = parse path

Why restrict this? Printing is fine in most programs — the claim here
is a boundary policy about which layer owns the console, and it is
wrong to impose on a CLI project whose libraries print by design.
Progress-reporting and CLI-support libraries print legitimately. The
rule is already kind-gated to libraries, and the gate is the tell that
it is policy, not defect detection — so it sits in the `restriction`
tier: off even under `--select all`, cherry-picked by a workspace that
has adopted the boundary, with
`[@litany.allow "suspicious-print-debugging: user-facing output"]` as
the audit trail for the deliberate printers.

Fires once per resolved reference to `print_endline`, `print_string`,
`Printf.printf`, `Printf.eprintf`, or `prerr_endline` — aliases
included: `let log = Printf.printf` is a printer — and only in units
whose roster kind is `Library`. Executables and tests print by right,
and a unit whose roster carries no kind (common under adapters whose
rosters say nothing yet) is deliberately silent: a metadata-gated rule
degrades to silence, never to guessing. `Printf.sprintf` and kin build
strings, `Format.printf` is unlisted in this version, and a shadowing
local `print_endline` resolves to a local declaration — none fire. No
fix: the remedy — a logging seam, a formatter parameter, deletion — is
a design decision.|}
    ~kind_gated:true ()

let printers =
  Pat.(
    idents
      [
        "Stdlib.print_endline";
        "Stdlib.print_string";
        "Stdlib.Printf.printf";
        "Stdlib.Printf.eprintf";
        "Stdlib.prerr_endline";
      ])

let rule =
  Rule.expr meta @@ fun u e ->
  match Unit.kind u with
  | Some Unit.Library -> (
      match Pat.run printers u e () with
      | Some () ->
          [ Finding.v ~loc:e.exp_loc "library code prints to the console" ]
      | None -> [])
  | Some Unit.Executable | Some Unit.Test | None -> []
