(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [unit] command: the one-unit in-build gate.
    [litany unit NAME --cmt PATH --source PATH] lints exactly one unit — its
    argv is the roster: no subprocess, no lock, no workspace query — printing
    findings in the compiler report format on standard error with standard
    output completely silent, exit 1 on findings (dune parses embedded locations
    from failing actions only). The default rule set runs and the workspace
    [litany] file is deliberately not read: the invocation is a build rule and
    must mean the same thing on every checkout. A unit that cannot be admitted
    is a refusal naming the skip (exit 2) — a one-unit gate that silently
    skipped would read as clean.

    Under dune the whole-workspace in-build lane is one user-written
    [litany check] rule ([doc/manual/build-integration.md]); this command is the
    per-module gate for build systems that wire one rule per unit. *)

val cmd : int Cmdliner.Cmd.t
