(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [if]-then-else with exactly one boolean-literal branch.

    Reports every [if c then t else e] where exactly one branch is the literal
    [true] or [false] (predefined-constructor identity): the conditional spells
    [(||)] or [(&&)] in longhand — [if c then true else e] is [c || e], and kin
    — and the message names the equivalent form. All four rewrites preserve
    evaluation order and effects.

    Literal conditions (suspicious-literal-condition's finding), two-literal
    branches (redundant-if-bool's, from which this family was split),
    non-boolean literal branches, and user-defined [True]/[False] constructors
    deliberately do not fire. The fix performs the table's rewrite with
    parenthesized operands when both needed slices are clean; every cell splices
    an operator spelling the rule never resolved, so all fixes are unsafe. *)

val rule : Litany.Rule.t
(** [rule] is [manual-boolean-operator]. *)
