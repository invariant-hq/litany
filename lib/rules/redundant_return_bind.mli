(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Binds whose scrutinee is the monad's own fresh [return].

    Reports two-argument applications of a known-lawful bind whose first
    argument is that pair's return applied to a value — the left identity law,
    so the callback applies to the value directly: [Option.bind] over
    [Option.some], [Result.bind] over [Result.ok], [Lwt.bind] and
    [Lwt.Infix.( >>= )] over [Lwt.return].

    Pairs match by declaration: arbitrary scrutinees, [Error], partial
    applications, and a project's own [bind]/[return] stay clean. No fix —
    naming the callback's argument is editorial. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-return-bind]. *)
