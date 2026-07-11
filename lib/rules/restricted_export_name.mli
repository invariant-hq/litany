(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Exported names the workspace's naming policy condemns.

    The configured naming policy over the unit's export surface: each
    [(forbid-suffix <suffix>)] form of the workspace's
    [(rule restricted-export-name …)] options condemns exported value and type
    names ending in the literal suffix, and [(max-underscores <count>)] condemns
    those carrying more underscores. The vocabulary is closed and enumerated —
    never a user-supplied regex — and each finding's message names the
    condemning option.

    The export surface is the seam's ({!Litany.Unit.exports}): the unit's
    interface when it has one — a name the [.mli] hides never fires — and the
    implementation's own inferred signature when it does not, so an ml-only unit
    exports every root declaration — executables and tests included: their root
    names are surface to their own readers, and the tier keeps the rule opt-in.
    Findings anchor at the implementation's matching root declaration, never in
    the [.mli]. Restrictions are tried in configured order; the first condemning
    one reports, one finding per offending name.

    Unconfigured, or configured with no restrictions, the rule is inert.
    Malformed suffixes and counts, duplicates, and unknown forms are positioned
    configuration errors (a refusal, nothing runs). Local names, module names,
    mid-name suffix occurrences, and names at the underscore limit deliberately
    do not fire; submodule members and [include]-satisfied exports are recorded
    false negatives. Restriction, nursery — outside [all], cherry-picked by
    exact name. No fix: renaming an export is an interface decision. *)

val rule : Litany.Rule.t
(** [rule] is [restricted-export-name], condemning nothing until configured. *)
