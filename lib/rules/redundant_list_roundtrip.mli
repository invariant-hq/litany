(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** List-to-sequence conversions immediately undone by [List.of_seq].

    Reports exactly [List.of_seq (List.to_seq xs)] when both conversions resolve
    to their [Stdlib.List] declarations and the inner application feeds the
    outer one directly — the expression copies [xs] through a sequence to end
    where it started. The compiler collapses [|>] into direct applications, so
    the piped spelling fires too.

    Shadowed or let-rebound names, intervening sequence work, the reverse
    direction, and other [of_seq] targets stay clean. The rule offers no fix:
    [List.of_seq] allocates a fresh list, so removing the roundtrip changes
    physical identity. Measured, OCaml 5.5.0 arm64 non-flambda: ~88 B and ~4 ns
    per element, and both conversion calls survive verbatim in [-dlambda]. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-list-roundtrip]. *)
