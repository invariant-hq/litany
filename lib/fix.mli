(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Source fixes attached to findings.

    A fix is a titled list of byte-range {!type:edit}s against a unit's editable
    source, tagged with an {!type:applicability} that says whether applying it
    preserves behavior. Rules construct fixes with {!safe_replace},
    {!unsafe_replace}, {!safe_delete}, or the general {!v}, and attach them to
    findings ([Finding.v]); the engine may downgrade a fix's applicability
    (preprocessed units: [Safe] becomes [Unsafe]; offset-inconsistent locations:
    any applicability becomes [Display]).

    Safety is earned, not asserted: a [Safe] fix's rule must ship a fixture
    whose fixed output compiles in CI, and the bare constructor {!v} defaults to
    [Unsafe]. Application mechanics (sorting, conflict deferral, digest
    re-check, reparse verification {e before} any write — a result that fails to
    reparse is never written, so there is nothing to roll back — atomic write)
    live in the fix applier, not here — this module is inert data.

    Edits are expressed in the byte coordinates of the editable source captured
    at join time ([Unit.Witness.source_digest] is the write baseline); an edit
    computed against other bytes must never be applied. *)

(** {1:applicability Applicability and availability} *)

(** The type for fix applicability. *)
type applicability =
  | Safe  (** Applying the fix preserves behavior. Applied by [--fix]. *)
  | Unsafe
      (** Applying the fix may change behavior; the fix's title says how.
          Applied only by [--fix --unsafe]. *)
  | Display
      (** Never applied; rendered as a suggestion only. The engine downgrades
          fixes to [Display] when their anchors are line-anchored
          (offset-inconsistent under a textual preprocessor). *)

val applicability_to_string : applicability -> string
(** [applicability_to_string a] is ["safe"], ["unsafe"], or ["display"] — the
    fix-line and JSON vocabulary. *)

(** The type for a rule's fix promise, declared in [Rule.meta] and enforced by
    the rule test suites and at registry construction: a [Never] rule whose
    callback returns a fix is a rule failure, and an [Always] rule's fixture
    must exercise a compiled [.fixed] golden.

    {b Note.} The first case is [Never], not [None], so rule code that matches
    [option] values constantly never shadows [Stdlib.None]. *)
type availability =
  | Never  (** The rule never returns a fix. *)
  | Sometimes  (** The rule returns a fix when it can slice the source. *)
  | Always  (** Every finding of the rule carries a fix. *)

val availability_to_string : availability -> string
(** [availability_to_string a] is ["never"], ["sometimes"], or ["always"] —
    [litany rules]' table vocabulary. *)

(** {1:edits Edits} *)

type edit = {
  span : Span.t;  (** The byte range replaced. *)
  text : string;
      (** The replacement bytes. [""] deletes the range; an empty [span] inserts
          [text] at its position. *)
}
(** The type for byte-range edits: replace [span] with [text]. *)

(** {1:fixes Fixes} *)

type t
(** The type for fixes. Invariant: a fix has at least one edit and its edits are
    pairwise conflict-free — non-overlapping (see {!Span.overlaps}), and no
    insertion point strictly inside a replaced range: the same relation
    [Apply.plan] documents, so a fix {!v} accepts is one the applier can apply.
*)

val v : ?applicability:applicability -> title:string -> edit list -> t
(** [v ~title edits] is a fix performing [edits], described to the user by
    [title]. [applicability] defaults to [Unsafe] — safety is earned.

    Raises [Invalid_argument] if [edits] is empty or two edits conflict
    (overlap, or an insertion point strictly inside a replaced range); both are
    programmer errors in the emitting rule. Checked in that order: emptiness
    first, then conflicts over the edits sorted by span. *)

val safe_replace : Location.t -> string -> title:string -> t
(** [safe_replace loc text ~title] is a [Safe] single-edit fix replacing the
    bytes under [loc] with [text]. Offsets are taken as by {!Span.of_location},
    which also documents the raising cases — dummy positions ([Location.none] on
    PPX-synthesized nodes) raise here, becoming a rule failure rather than a
    dropped finding. The idiom is normative: construct fixes only from locations
    whose text you sliced — [Unit.splice] is the gate, and its [None] answer
    means ship the finding without the fix. *)

val unsafe_replace : Location.t -> string -> title:string -> t
(** [unsafe_replace loc text ~title] is {!safe_replace} with applicability
    [Unsafe]. *)

val safe_delete : Location.t -> title:string -> t
(** [safe_delete loc ~title] is [safe_replace loc "" ~title]: a [Safe] fix
    deleting the bytes under [loc]. *)

(** {1:queries Queries} *)

val title : t -> string
(** [title f] is the user-facing description of [f], shown on the finding's fix
    line and in fix previews. *)

val applicability : t -> applicability
(** [applicability f] is [f]'s applicability after any engine downgrades. *)

val edits : t -> edit list
(** [edits f] is [f]'s edits, in increasing {!Span.compare} order of their
    spans. *)

(** {1:updating Updating} *)

val with_applicability : applicability -> t -> t
(** [with_applicability a f] is [f] with applicability [a]. This is the engine's
    downgrade hook; rules have no reason to upgrade a fix and the rule test
    suites treat an upgrade as a rule failure. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf f] formats [f]'s title, applicability, and edit spans for debugging.
    The output is not stable. *)
