(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Engine-end-to-end harness for the per-rule suites.

    Each rule suite compiles a fixture library through dune and asserts the
    rule's findings by running the engine over the fixture's real artifact —
    never by calling the rule's callback directly. Positive lines carry a
    [(* FIRE *)] marker in the fixture source, so the fixture is its own
    expectation. *)

val assert_all_resolve : Litany.Naming.Resolver.t -> unit
(** [assert_all_resolve r] asserts the creation-time literal audit: every name
    literal recorded by [Litany.Pat.Registry] — each [ident], [idents], and
    [typ] literal of every rule linked into the suite binary — must still denote
    something under [r]. A literal probing [`Unresolved] (defining unit's cmi
    present, name absent — the typo signal) fails the test, naming each
    offender; literals whose defining unit has no cmi on [r]'s search path
    ([Lwt.*] in a workspace without lwt) are out of audit reach and pass.
    {!report} and {!project_report} run it on every fixture run, so a typo in an
    arm no fixture exercises is a failing suite, not a silently dead arm. *)

val report :
  ?cmti:string ->
  ?kind:Litany.Roster.kind ->
  ?visibility:Litany.Roster.visibility ->
  Litany.Rule.t ->
  source:string ->
  cmt:string ->
  Litany.Engine.Report.t
(** [report r ~source ~cmt] runs the engine with [r] as the only selected rule
    over the single-entry roster joining [source] with [cmt]. The resolver
    searches [cmt]'s directory, the toolchain's standard library, and the
    toolchain's unix otherlib directory when present, so canonical [Stdlib.*]
    and [Unix.*] names resolve as in a real run. [cmti] names the unit's
    interface artifact for the suites whose rule reads [Litany.Unit.interface];
    [kind] sets the roster entry's stanza kind and [visibility] the owning
    library's visibility, for the suites whose rule gates on them; all default
    to none. *)

val fire_lines : source:string -> int list
(** [fire_lines ~source] is the ascending list of 1-based line numbers of
    [source] whose text contains the [(* FIRE *)] marker. *)

val check_markers :
  ?message:string ->
  ?cmti:string ->
  ?kind:Litany.Roster.kind ->
  ?visibility:Litany.Roster.visibility ->
  Litany.Rule.t ->
  source:string ->
  cmt:string ->
  unit
(** [check_markers r ~source ~cmt] asserts, via the engine end to end: no rule
    failures, nothing dropped, every finding emitted by [r], every finding's
    message is [message] when given, and the findings' start lines are exactly
    {!fire_lines} — the fixture's own markers. *)

val shape : Litany.Engine.Report.t -> (string * string * int * int) list
(** [shape rep] is [(rule, path, start offset, stop offset)] per finding, in
    report order — the byte-precise assertion the span-sensitive suites use. *)

val check_fixed :
  ?unsafe:bool ->
  Litany.Rule.t ->
  source:string ->
  cmt:string ->
  golden:string ->
  unit
(** [check_fixed r ~source ~cmt ~golden] asserts the fix round-trip over the
    engine end to end: no rule failures and nothing dropped; an [Always] promise
    puts a fix on every kept and expected finding; the fixes of the kept {e and}
    expected findings — the rule suites are the sole place expected findings'
    fixes apply — plan without conflicts (a conflict is a fixture defect: split
    the fixture); and patching [source]'s bytes with the selected fixes yields
    exactly [golden]'s bytes. Pure planning and patching ({!Litany.Apply.plan},
    {!Litany.Apply.patch}) — no file is written. The golden's own compilation is
    each fixture's plain dune rule: the fixture directory copies the golden to a
    module of its own and builds it, and the suite depends on the resulting cmt,
    so [dune runtest] proves Safe is a compiled golden, not a vibe.

    [unsafe] (default [false]) plans at the Unsafe level, as [--fix --unsafe]
    does: a rule with Unsafe cells pins their rewrites against a second golden
    the same way — an Unsafe fix may change behavior, never fail to compile. *)

(** {1:project Project-rule suites} *)

type project_unit
(** The type for one unit of a project-rule fixture workspace. *)

val project_unit :
  ?cmti:string ->
  ?interface_source:string ->
  ?library:string ->
  ?visibility:Litany.Roster.visibility ->
  ?kind:Litany.Roster.kind ->
  source:string ->
  cmt:string ->
  unit ->
  project_unit
(** [project_unit ~source ~cmt ()] is a fixture-workspace unit. [library]
    defaults to ["fixlib"], [visibility] to [Private] (so exports are
    candidates, not roots), [kind] to [Library] — every default keeps the roster
    project-capable. *)

val project_report :
  ?complete:bool ->
  Litany.Rule.t list ->
  project_unit list ->
  Litany.Engine.Report.t
(** [project_report rules units] runs the engine with [rules] over the
    multi-entry roster of [units] — [complete] (default [true]) asserted so the
    roster is project-capable. Resolver search covers every unit's artifact
    directory, the toolchain's standard library, and its unix otherlib. *)

val check_project_marshal : Litany.Rule.t -> project_unit list -> unit
(** [check_project_marshal r units] loads each unit and runs [r]'s [collect] —
    [Litany.Rule.project] seals each fact as one [Marshal] frame right there (no
    sharing flags — a closure or custom block raises, failing the test): the
    Marshal-safety law, discharged in the rule's own suite. [report] over the
    sealed concatenation must be deterministic, finding for finding — the decode
    at the report seam is the round trip. *)
