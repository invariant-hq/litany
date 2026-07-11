(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [explain] command: one rule's full documentation — header (name,
    summary), policy line (group, derived severity, stability, since, fix
    promise, default state), then the rule's Markdown doc verbatim, all from
    [Litany.Rule] metadata. A tombstone alias resolves with the selection
    surface's rename note on standard error; an unknown name is a refusal with a
    did-you-mean over names and aliases. *)

val cmd : int Cmdliner.Cmd.t
