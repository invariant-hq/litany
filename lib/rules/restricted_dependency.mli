(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** References to dependencies the workspace forbids.

    The configured deny-list over resolved identities: each
    [(forbid <path> (use "<replacement>"))] form of the workspace's
    [(rule restricted-dependency …)] options names a module — a capitalized last
    component: one compilation unit ([Str]), or a dotted path resolved by
    signature walk ([Stdlib.Obj]) — or a value ([Stdlib.invalid_arg]), and every
    reference resolving to a forbidden declaration reports the configured
    replacement verbatim.

    The options schema is the contract, remedies included: a [forbid] without a
    [(use …)] remedy is a configuration error — every ban names its replacement,
    so each finding argues its own case. Malformed paths, duplicate forbids, and
    unknown forms are positioned configuration errors too (a refusal, nothing
    runs); a well-formed path that does not resolve in the linted workspace
    matches nothing — never an error. Unconfigured, or configured with no
    forbids, the rule is inert.

    Identity, not spelling: aliases and [open]s fire; shadowing definitions,
    same-named wrapper modules declared in other units, and a forbidden module's
    constructors and types do not. Restriction, nursery — outside [all],
    cherry-picked by exact name. No fix: every replacement is a migration. *)

val rule : Litany.Rule.t
(** [rule] is [restricted-dependency], forbidding nothing until configured. *)
