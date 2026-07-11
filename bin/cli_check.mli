(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [check] command: joins each candidate unit's source with its compiled
    artifact, runs the selected rules over every admitted unit, and renders the
    report — exit code 0 clean, 1 findings, 3 rule failure. The workspace-root
    [litany] file is read first ([Cli_config]): its selection feeds the same
    resolution as [--select]/[--ignore] (a given flag replaces the file's
    corresponding lists), its per-path blocks become the engine's report filter,
    and its rule blocks configure rules' declared option schemas — every config
    mistake is a positioned refusal, exit 2. [--list-units] prints the admission
    listing instead of running rules.

    [--fix] applies the findings' safe fixes ([--unsafe] adds the unsafe ones;
    suppressed and expected findings are never fixed; a fix whose result does
    not reparse is a fixer bug — file untouched, exit 3). Under the dune
    adapter, convergence spans builds: after a pass that applied fixes the
    driver rebuilds, re-joins, and re-lints, picking up deferred conflict
    losers, capped at 3 passes with per-pass summary lines; a post-fix build
    failure stops the run with the applied-fix list and the exact stderr line
    [files were modified; git diff shows the applied fixes] (exit 2). Under
    [--cmt-root] or [--no-build] exactly one pass runs, ending with the
    rebuild-to-converge message. At render, every admitted source is re-checked
    against its analysis-time bytes; a unit the user edited mid-run is demoted
    to a modified-during-run skip rather than reported. *)

val cmd : int Cmdliner.Cmd.t
