(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Binds whose callback is the monad's own bare [return].

    Reports two-argument applications of a known-lawful bind with its return
    passed as the callback — the right identity law, so the expression is just
    the bound computation: [Option.bind] with [Option.some], [Result.bind] with
    [Result.ok], [Lwt.bind] and [Lwt.Infix.( >>= )] with [Lwt.return].

    Pairs match by declaration, so a project's own [bind]/[return] — lawful or
    not — never fires; each listed pair is an audited lawfulness claim. Lambda
    callbacks and [let*] syntax stay clean. The identity is structural;
    physically only the [Some]/[Ok] arms are rebuilt — [None] and [Error] pass
    through the bind intact ([==] holds), and Lwt yields a fresh promise of the
    same value (verified OCaml 5.5.0). The rewrite to the computation itself has
    no automatic fix in this release — the promise flips to [Sometimes] when it
    lands. *)

val rule : Litany.Rule.t
(** [rule] is [redundant-bind-return]. *)
