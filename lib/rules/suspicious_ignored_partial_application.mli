(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [ignore] applied to a value that is still a function.

    Reports [ignore e] when [ignore] resolves to its [Stdlib] declaration and
    [e]'s type head is an arrow — a discarded closure whose remaining arguments,
    and therefore effects, never happen. It fires only on the shapes compiler
    warning 5 deliberately skips — a bound closure, an alias, a literal [fun]:
    applications, method sends, and the statement spines typecore walks are
    warning 5's own territory and refuse, as does its documented constraint
    escape ([ignore (e : _ -> _)]). The pipeline spellings ([e |> ignore],
    [ignore @@ e]) reach the rule as the same application.

    Saturated calls, shadowed [ignore], non-function arguments, and abbreviation
    heads stay clean; a literal closure fires. No fix: the remedy is the missing
    arguments, or the typed discard [let (_ : _ -> _) = e]. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-ignored-partial-application]. *)
