(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Findings: one diagnostic at one owned location.

    A finding pairs a location in a unit's editable source with a message,
    optionally a {!Fix.t}. Rules construct findings with {!v} and return them
    from their callbacks; everything else about a finding's life — the emitting
    rule's name, its severity, whether it survives the emit contract — is
    decided by the engine, not encoded here.

    {b The emit contract} (enforced by the engine, stated here because it is the
    contract of {!val:loc}): a finding is kept only if its location is (a)
    non-ghost, (b) inside the unit's own editable source file, (c)
    offset-consistent — its positions agree with that file's actual line index
    (see [Source.consistent]) — and (d) when the unit's pre-PPX parse exists
    ([Unit.parsetree]), corroborated by a node span in that parse: a finding can
    only anchor at a span that existed in the editable source (a PPX that copies
    a whole user span onto generated code can still surface a finding at that
    user span). In units whose editable source does not parse, (d) is waived:
    findings are kept under (a)–(c) alone and the summary notes the reduced
    guarantee for that unit. Offset-inconsistent findings degrade to
    line-anchored renderings without carets and their fixes to [Display];
    everything else failing the contract is dropped and counted, never rendered.
    Findings are deduplicated by (rule, location, message) — the rule name
    paired by the engine at the report seam ([Engine.Report]), never a field
    here.

    Severity is not a field either: it derives from the emitting rule's group at
    render time (see [Rule.Severity]). *)

(** {1:findings Findings} *)

type t
(** The type for findings. *)

val v : ?fix:Fix.t -> loc:Location.t -> string -> t
(** [v ~loc message] is a finding anchored at [loc] with user-facing [message].
    [message] is one sentence, no trailing period needed, stating the problem in
    the code's terms.

    - [fix] is a suggested edit; a rule may only supply one if its meta promises
      [Sometimes] or [Always] (see {!Fix.availability}). Defaults to no fix.

    [loc] must lie in the editable source of the unit the callback was given;
    findings elsewhere are dropped by the emit contract. *)

(** {1:queries Queries} *)

val loc : t -> Location.t
(** [loc f] is [f]'s anchor location in the unit's editable source. *)

val message : t -> string
(** [message f] is [f]'s user-facing message. *)

val fix : t -> Fix.t option
(** [fix f] is [f]'s suggested fix, if any, with any engine downgrade already
    applied (see {!Fix.applicability}). *)

(** {1:fmt Formatting and comparing} *)

val equal : t -> t -> bool
(** [equal f f'] is [true] iff [f] and [f'] agree on (location, message). The
    engine's deduplication key is (rule, location, message), with the rule name
    it pairs at the report seam. Fixes do not participate. *)

val compare : t -> t -> int
(** [compare f f'] orders findings by source path, then start byte offset, then
    end byte offset, then message. The renderers' total order — (path, start
    offset, rule name, end offset, message) — is the report's
    ([Engine.Report.findings]), which interleaves the paired rule name as its
    third key. The order is compatible with {!equal}. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf f] formats [f] for debugging — location, message, fix presence.
    Renderers, not [pp], produce user output. The output is not stable. *)
