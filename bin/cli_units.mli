(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [units] command: enumerates the workspace's units exactly as [check]
    does (dune adapter by default, [--cmt-root] for the walk) and serializes the
    roster. [--save FILE] writes the canonical unit file
    ([Litany.Adapter.Unit_file.encode] — csexp, byte-deterministic, lossless for
    any path bytes), the one interface any build system targets and
    [litany check --units] consumes; [--dump] (the default action) pretty-
    prints the same document as human s-expressions. Spawning dune inside a dune
    action is refused; [--no-build] skips the [@check] build, leaving stale
    entries to skip at consumption time. *)

val cmd : int Cmdliner.Cmd.t
