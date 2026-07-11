(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [rules] command: the catalog table — one line per built-in rule with
    name, group, stability tier, fix promise, on-by-default bit, and summary,
    plus one counted trailer line. Derived entirely from [Litany.Rule] metadata
    (the one-declaration law), in catalog order. *)

val cmd : int Cmdliner.Cmd.t
