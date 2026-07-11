(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-str-formatter" ~group:Rule.Suspicious ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"reference to the process-global Format.str_formatter"
    ~doc:
      {|`Format.str_formatter` is one process-global buffer formatter. Two
interleaved users corrupt each other's output — in a multi-fiber or
multi-domain program interleaving is the normal case — and partial
output survives in the buffer across exceptions, so the next
`flush_str_formatter` answers with another computation's bytes
prepended. fmt guards its own API against the value by raising on it;
`Format.asprintf` is the total replacement.

    (* bad *)  Format.fprintf Format.str_formatter "%a" pp v;
               Format.flush_str_formatter ()
    (* good *) Format.asprintf "%a" pp v

Fires once per reference resolving to `Stdlib.Format.str_formatter` or
`Stdlib.Format.flush_str_formatter` in a Library-kind unit — spelled
directly, through an alias, or via `open`; a shadowing local
`Format` never fires. Units without kind metadata, and executables
(where a single-threaded scratch buffer can be correct in practice),
stay silent — the library boundary is where the value's process-global
sharing meets unknown callers. No body-shape analysis. The `ifprintf`
sink shape (`Format.ifprintf Format.str_formatter fmt`) is the known
benign case and still fires: suppress it with `[@litany.allow]` where a
sink formatter is deliberate. The declared `Sometimes` fix — the adjacent
print-then-flush pair rewriting to `Format.asprintf` — is not emitted
in this version: the pair spans two findings' nodes and attaching the
rewrite needs either an enclosing-context capability or a
carrier-finding decision (recorded gap); the promise stays
`Sometimes`, promising nothing per-finding.|}
    ~kind_gated:true ()

let message =
  "Format.str_formatter is one process-global buffer; use Format.asprintf"

let global =
  Pat.(
    idents
      [ "Stdlib.Format.str_formatter"; "Stdlib.Format.flush_str_formatter" ])

let rule =
  Rule.expr meta @@ fun u e ->
  if Unit.kind u <> Some Unit.Library then []
  else
    match Pat.run global u e () with
    | None -> []
    | Some () -> [ Finding.v ~loc:e.exp_loc message ]
