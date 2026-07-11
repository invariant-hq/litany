(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Chains of three or more [( ^ )] segments.

    Reports [Stdlib.( ^ )] applications whose right operand is itself a
    [Stdlib.( ^ )] application: right associativity makes each added segment
    recopy the segments after it, where [String.concat] allocates once.
    Measured, OCaml 5.5.0 arm64 non-flambda: eight right-associated 1 MB
    segments allocate 35 MB against [String.concat]'s 8 MB — waste growing with
    the square of the segment count.

    Two-segment concatenations, rebound operators, and left-parenthesized chains
    stay clean. One finding per maximal chain, anchored where the chain first
    exceeds the threshold. The config option [(max-segments <n>)] raises the
    tolerated chain length from its default 2 — the first consumer of the
    per-rule option schema. Pedantic, nursery, off by default; no fix. *)

val rule : Litany.Rule.t
(** [rule] is [quadratic-string-concat-chain], at the default threshold. *)
