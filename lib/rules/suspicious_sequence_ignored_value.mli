(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Pure projections discarded where warning 10 cannot speak.

    Reports a sequence left-hand side that is a saturated application of an
    enumerated pure projection ([List.hd], [Option.get], [Result.get_ok],
    [Result.get_error], [fst], [snd], [List.nth], [List.assoc], [List.assq],
    [List.find], [Hashtbl.find]) whose result type is a bare type variable — the
    one head shape the compiler's non-unit-statement warning must stay silent
    on, and the discard where the returned value was the entire point.

    Concrete result heads (warning 10 already fires — the Tvar guard is the
    no-duplicate boundary), [ignore (…)], effectful pops ([Queue.pop],
    [Stack.pop]), rebound or shadowed names, and non-enumerated callees
    ([raise], [List.find_opt]) deliberately do not fire. Statement positions
    other than the sequence left-hand side are recorded extensions. No fix: the
    remedy is deciding what to do with the value. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-sequence-ignored-value]. *)
