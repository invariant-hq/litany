(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Mapped intermediate lists consumed directly by list concatenation.

    Reports [List.concat (List.map f xs)] and [List.flatten (List.map f xs)]
    when both functions resolve to their [Stdlib] declarations and the
    two-argument map application feeds the concatenation directly — the mapped
    list of lists exists only to be traversed and discarded. Measured, OCaml
    5.5.0 arm64 non-flambda: +24 B per element — the intermediate spine exactly,
    +25% allocation on two-element results; both forms are linear and nothing
    fuses at [-O3] — a constant-factor cost, not an asymptotic one.

    The compiler collapses [|>] on a saturated map into that shape, so
    [List.map f xs |> List.concat] fires too. Shadowed or let-rebound names,
    [List.concat_map] itself, partial applications, and intervening expressions
    stay clean. No automatic fix in this release — the promise flips to
    [Sometimes] when the [List.concat_map] fix lands. *)

val rule : Litany.Rule.t
(** [rule] is [needless-list-map-before-concat]. *)
