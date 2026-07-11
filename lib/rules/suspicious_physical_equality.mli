(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Physical comparisons whose operands are proved non-immediate.

    Reports two-argument applications of [Stdlib.(==)] and [Stdlib.(!=)] when at
    least one operand's type is proved non-immediate: a function, a tuple, or a
    predefined boxed type ([string], [bytes], [float], [array], and kin). On
    boxed values physical identity depends on allocation history, so the
    comparison rarely means what structural equality would.

    Operands of unknown immediacy (type variables, abbreviations, user-defined
    types), shadowed operators, and partial applications stay clean. Physical
    identity can be intentional, so the rule offers no fix. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-physical-equality]. *)
