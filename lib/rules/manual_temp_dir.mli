(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Temp files removed and re-created as directories.

    Reports the [Filename.temp_file] / remove / mkdir sequence: removing the
    exclusively-created file and re-creating its name as a directory forfeits
    the exclusivity that is [temp_file]'s whole security contract (CWE-377).
    [Filename.temp_dir] is the atomic form and the message's remedy — verified,
    OCaml 5.5.0 arm64 non-flambda: a racer wins the remove/mkdir window (the
    victim gets [File exists] and the surviving directory carries the racer's
    0o755, not the intended 0o700), while the atomic [mkdir] has no window. Path
    identity is the bound declaration's, never spelling. The Safe fix rewrites
    the direct remove-then-mkdir shape under textual gates (exact callee
    spelling, whitespace-only argument gaps, literal permissions, no comment in
    the deleted region); any refused gate refuses the fix, never the finding.
    First consumer of [Pat.apply_opt] — [temp_file]'s omitted [?temp_dir]
    refuses the exact-shape [Pat.apply]. *)

val rule : Litany.Rule.t
(** [rule] is [manual-temp-dir]. *)
