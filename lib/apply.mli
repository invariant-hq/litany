(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Single-file fix application: one pass, verified writes.

    The applier takes one file's fix candidates — findings' fixes paired with
    their emitting rules' names — and applies them to the file in one pass:
    {!plan} filters by applicability and drops conflicting fixes
    deterministically, {!patch} rewrites the bytes, and {!file} is the IO shell
    that re-checks the write baseline, verifies the patched bytes still parse,
    and writes atomically (temp file + rename in the file's directory). The
    invariant enforced here: a fix never writes unverified bytes — the editable
    source's digest captured at admission must still match at write time, and a
    patched result that does not parse is a fixer bug that leaves the file
    untouched, never a written one.

    One pass means one pass: conflict losers are reported, not retried — the
    build-spanning convergence loop that re-runs, re-joins, and applies deferred
    losers is the [--fix] driver's. Callers group candidates per file; nothing
    here spans files.

    The applier is driver machinery — [litany check --fix] and the rule test
    suites call it; rules never see it. Suppressed and expected findings are
    excluded before candidates reach the applier ([--fix] applies kept findings
    only; the suites' golden helper is the sole exception, applying expected
    findings' fixes to produce the [.fixed] golden). *)

(** {1:candidates Candidates} *)

type candidate = { rule : string; fix : Fix.t }
(** The type for application candidates: one finding's fix, tagged with its
    emitting rule's name — the tiebreak key conflicts resolve by. *)

(** {1:planning Planning} *)

type plan
(** The type for one file's application plan: the candidates partitioned into
    {!selected}, {!conflicting}, and {!excluded}. Pure — planning never touches
    the file. *)

val plan : ?unsafe:bool -> candidate list -> plan
(** [plan cands] partitions [cands]: candidates whose applicability is outside
    the requested level are {!excluded} ([Fix.Safe] applies; [Unsafe] only under
    [unsafe], defaulting to [false]; [Display] never); the rest are ordered by
    (first edit span, rule name) and kept greedily — a candidate any of whose
    edits conflicts with an already-kept candidate's is {!conflicting}, dropped
    deterministically by that order. Two edits conflict when they overlap
    ({!Span.overlaps}) or when one is an insertion point strictly inside the
    other's replaced range — applying both would shift bytes the other was
    computed against. Insertions at a replaced range's boundary, and two
    insertions at the same point, do not conflict. *)

val selected : plan -> candidate list
(** [selected p] is the candidates {!file} will apply, in application order —
    (first edit span, rule name). *)

val conflicting : plan -> candidate list
(** [conflicting p] is the conflict losers in the same order — reported as not
    applied; a later pass over rebuilt artifacts can pick them up. *)

val excluded : plan -> candidate list
(** [excluded p] is the applicability-filtered candidates, in input order —
    [Display] fixes always, [Unsafe] fixes unless [plan] was told [unsafe]. *)

(** {1:patching Patching} *)

val patch : string -> Fix.edit list -> string
(** [patch s edits] is [s] with every edit applied — each [span] replaced by its
    [text], all spans in [s]'s coordinates. [edits] may arrive in any order but
    must be pairwise conflict-free (see {!plan}); insertions at the same point
    land in list order. Pure: callers slice and verify, [patch] only rewrites.

    Raises [Invalid_argument] if an edit's span exceeds [s]'s length or two
    edits conflict — both mean the edits were not computed against [s], a
    programmer error in the caller. *)

(** {1:correcting Correcting} *)

val correct :
  ?unsafe:bool ->
  string ->
  candidate list ->
  (string, [ `Fixer_bug of string | `Unverifiable ]) result
(** [correct bytes cands] is the never-write-unverified-bytes discipline as a
    pure function — one home for plan → patch → reparse-verify, used by
    {!file}'s disk mode and available to any worker proposing corrections
    without touching disk: [bytes] with [cands]'s planned fixes applied (as
    {!plan}, under [unsafe]), provided the original parses and the result parses
    again.

    [`Unverifiable] when [bytes] does not parse — checked first: the applier
    never verifies what it cannot reparse, and no fix is blamed for bytes the
    plan never owned. [`Fixer_bug why] when an edit exceeds bounds, the patched
    result does not parse, or — with at least one fix selected — the patched
    result is byte-identical to [bytes]: a fix whose output equals its input
    converges nowhere, and writing it unconditionally would re-produce the same
    finding on every pass. The emitting rule constructed a wrong fix; [why] is
    the report's wording. An empty selection is not a bug: the result is then
    [Ok bytes], unchanged. Pure: nothing is read or written. *)

(** {1:applying Applying} *)

(** The type for one file's application result. No arm but [Applied] writes
    anything. *)
type outcome =
  | Applied  (** The plan's {!selected} fixes were written, atomically. *)
  | Nothing_to_apply
      (** {!selected} is empty — every candidate excluded or conflicting; the
          file was not opened for writing. *)
  | Stale
      (** The file's bytes no longer match [baseline]: the source changed
          between analysis and write, so every fix was computed against bytes
          that no longer exist. Discarded, not written — re-run the analysis. *)
  | Fixer_bug
      (** The patched bytes do not parse as an implementation, an edit exceeded
          verified bounds, or the selected fixes left the bytes unchanged (a fix
          whose output equals its input can never converge) while the original
          bytes parse — an emitting rule constructed a wrong fix. The file is
          untouched; the driver reports it as a bug in the selected rules. *)
  | Unverifiable
      (** The original bytes do not parse, so reparse verification is impossible
          (cppo sources and kin). Nothing written — even when the patched bytes
          happen to parse: the applier never writes what it cannot verify, and a
          patch that "repairs" an unparsable source into OCaml rewrote bytes it
          does not own. *)
  | Io_error of string
      (** The file could not be read or the atomic write failed; the message is
          the system error. A failed write never leaves a partial file — the
          temp file is removed and the target keeps its bytes. *)

val file :
  ?unsafe:bool ->
  path:string ->
  baseline:string ->
  candidate list ->
  plan * outcome
(** [file ~path ~baseline cands] plans [cands] (as {!plan}, under [unsafe]) and
    applies the selected fixes to [path]: read the bytes, check them against
    [baseline] — the 16-byte digest of the editable source captured at admission
    ([Unit.Witness.source_digest]), matched under either digest algorithm
    exactly as admission matches — patch, verify the result parses, then write
    atomically: the patched bytes go to a temp file beside [path]'s resolved
    target (keeping its permissions), flushed to disk, and renamed over it, so a
    crash leaves either the old file or the new one, never a mix. A symlinked
    [path] is written through — the link stays a link and its target gets the
    bytes. The digest check runs on the freshly read bytes; the microseconds
    between that read and the rename are the residual race no digest can close
    (only a file lock could), which is why [--fix]'s ownership story is the
    single-writer model, not this guard. The returned plan is the partition
    every outcome refers to. *)
