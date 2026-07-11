(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Scalar conversions immediately undone by their inverse.

    Reports [outer (inner x)] for the stdlib compositions proved identities by
    contract: [int_of_string] of [string_of_int], [bool_of_string] of
    [string_of_bool], [Char.chr] of [Char.code], [of_string] of [to_string] for
    [Int32]/[Int64]/[Nativeint], and [Bytes.to_string] of [Bytes.of_string].
    Both names must resolve to their [Stdlib] declarations with the inner
    application feeding the outer directly; pipeline spellings collapse and
    fire.

    The canonicalizing reverse directions, the range-checking
    [Char.code (Char.chr n)], the mutable-aliasing
    [Bytes.of_string (Bytes.to_string b)], the lossy float pair, shadowed
    conversions, and work between the two stay clean. The fix (the argument
    itself) is Safe for the unboxed pairs only; boxed and copying pairs report
    without one, since replacement changes physical identity. Measured, OCaml
    5.5.0 arm64 non-flambda: the compiler folds none of the pairs ([-dlambda]);
    the int/string roundtrip costs ~112 B and ~67 ns per call, the float pair
    measured lossy at [1. /. 3.], and the Bytes pair measured copying. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-conversion-roundtrip]. *)
