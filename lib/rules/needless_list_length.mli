(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** List-length comparisons that are exactly emptiness tests.

    Reports comparisons of a [Stdlib.List.length] application with an integer
    literal zero or one when the relation is logically equivalent to emptiness
    or non-emptiness — [length = 0], [length <> 0], [length > 0], [length <= 0],
    [length >= 1], [length < 1] — in either operand order. [List.length]
    traverses the complete list spine; testing the outer constructor takes
    constant time. Verified, OCaml 5.5.0 arm64 non-flambda: the compiler does
    not optimize this — only the [[]] case inlines and every non-empty list
    calls [length_aux] to walk the full spine, while [xs = []] is one immediate
    compare; ~103 ns against ~0.7 ns per test at n=100 (~150x).

    Shadowed functions or operators, other constants, relations not equivalent
    to emptiness, labeled or partial applications, and unresolved identities
    stay clean. The fix ([compare with []]) rewrites the comparison to [xs = []]
    or [xs <> []], preserving polarity; it ships when the operand's source
    slices cleanly. *)

val rule : Litany.Rule.t
(** [rule] is [needless-list-length]. *)
