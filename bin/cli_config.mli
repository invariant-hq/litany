(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [litany] file's driver wiring: discovery, validation, catalog
    configuration, and the per-path report filter.

    The workspace-root [litany] file is read here (the config domain is pure —
    [Litany.Config_file] never does IO), validated against the rule catalog, and
    turned into the three things the check command consumes: the configured
    catalog (each [(rule <name> <options>)] form applied through
    [Litany.Rule.configure]), the effective selection tokens (file and flags
    merged under the documented precedence), and the engine's per-path [keep]
    filter. Every config error is a refusal — exit 2 with a
    [<file>:<line>:<col>: <message>] position, nothing runs. *)

type t
(** The type for loaded configurations: the parsed file (or the empty
    configuration when no file exists) plus its display path. *)

val load : root:string -> (t, int) result
(** [load ~root] reads and validates [root]'s [litany] file. An absent file is
    [Ok] with the empty configuration; an unreadable file, a parse error, an
    unknown name ([Litany.Config_file.check_names] over the catalog's
    vocabulary), or an engine-owned audit name used as a selection token is a
    printed refusal, [Error] carrying the exit code. *)

val configured_catalog : t -> (Litany.Rule.t list, int) result
(** [configured_catalog c] is the launch catalog with [c]'s
    [(rule <name> <options>)] forms applied — each resolved by name or tombstone
    alias and passed through [Litany.Rule.configure], in catalog order. A rule
    configured twice through an alias-and-name pair, or an option payload its
    rule refuses, is a printed refusal. *)

val configured_rule_names : t -> string list
(** [configured_rule_names c] is the resolved rule name of each
    [(rule <name> <options>)] form, in file order — tombstone spellings resolve
    to the current name. The check driver compares them against the selected set
    and warns [rule "X" is configured but not selected] for any left out:
    options configure a rule, they never select it, and a configured-but-silent
    rule is otherwise invisible. The warning is general — any rule's options can
    end up unselected — and it is a warning, not a refusal: an options block for
    a rule another lane selects is legitimate. *)

val tokens :
  t ->
  cli_select:string list ->
  cli_ignore:string list ->
  string list * string list
(** [tokens c ~cli_select ~cli_ignore] is the effective [(select, ignore)] token
    lists. Precedence is exact: a non-empty [cli_select] replaces the file's
    [select] {e and} [extend] together; a non-empty [cli_ignore] replaces the
    file's [ignore]; each flag independently, and an absent flag leaves the
    file's list in force. The file's own resolution is [select @ extend], with
    an absent or empty [select] reading as [default] when [extend] is present
    (extend is additive on top of the default set, never a replacement of it).
    Empty results mean "no tokens" — [Litany.Rule.select] then applies its own
    [default]. *)

val keep :
  t -> catalog:Litany.Rule.t list -> (path:string -> rule:string -> bool) option
(** [keep c ~catalog] is the engine's per-path report filter compiled from [c]'s
    [(per-path ...)] forms, or [None] when there are none. A finding is dropped
    when some per-path form's globs match the unit's path and some of its
    [ignore] tokens mention the emitting rule — token semantics mirror selection
    ([all] the stable set, [default] the on-by-default set, [nursery] the tier,
    a group its stable rules, a name or alias its rule), with one deliberate
    widening: [all] drops {e every} report on matching paths, engine audit
    findings included, because "ignore this path" must not leave the auditors
    talking. Paths that are not canonical workspace-relative paths are never
    matched — filtering is best-effort selection, not a correctness gate. *)

val closed_world : t -> bool
(** [closed_world c] is the file's [closed-world] bit. When set, the check
    command swaps the project rules to their closed-world forms: public-library
    exports become candidates instead of roots. *)
