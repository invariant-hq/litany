(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Recursive functions that hand-roll [List.map]'s recursion.

    Reports bindings whose body is exactly the two-case list recursion
    [[] -> []] / [x :: xs -> E :: self … xs] — every parameter passed through
    the recursion unchanged, the bound tail in the list position (any parameter
    position), and the head expression using neither the tail nor the function
    itself.

    The naive form is not an effect-for-effect [List.map]: its heads evaluate
    right-to-left where [List.map] runs left-to-right (traces [321] against
    [123]), and 5.5's growable stacks retire the old overflow motivation. The
    perf case stands — measured, OCaml 5.5.0 arm64 non-flambda: TRMC [List.map]
    is ~2x the naive recursion (27.5 ms against 56.5 ms at 1M elements).

    Guarded or extra cases, alias patterns, heads that read the tail, arguments
    other than the bound tail, user-defined [(::)]/[[]] constructors, and
    same-named outer functions deliberately do not fire. Self-calls of arity
    four or more are a recorded false negative. *)

val rule : Litany.Rule.t
(** [rule] is [manual-list-map]. *)
