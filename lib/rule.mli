(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Rules: one declaration, one pure callback.

    A rule is one value: metadata ({!val:meta}) plus a callback fixed by its
    constructor to one node kind. Callbacks are pure — they receive the
    {!Unit.t} (or {!Source.t}) and the node, and return findings; the engine
    owns traversal, so a rule can neither skip nor re-enter it, and dispatch is
    kind-indexed: a rule pays only at the nodes its constructor subscribes it
    to.

    One declaration is the law: [litany rules], [litany explain], the docs site,
    config validation, and JSON metadata all derive from {!val:meta}, and its
    promises are checked — a {!Fix.availability} of [Never] with a callback that
    returns a fix is a rule failure, and every [Always] rule's fixture must
    exercise a compiled [.fixed] golden.

    Group is policy: the {!Group} names the semantic category, and severity plus
    on-by-default derive from it at render time; nothing per-finding. A
    [Stability.Nursery] rule is off regardless of group and graduates by corpus
    evidence without changing name or group.

    Rule failures are isolated: a callback that raises fails that rule on that
    unit, the run continues, and the exit code becomes 3. *)

(** {1:policy Groups, stability, severity} *)

(** Semantic categories. *)
module Group : sig
  (** The type for rule groups — the semantic category of what a rule detects.
      Selection by group name ([select = ["style"]]) and severity both derive
      from it. *)
  type t =
    | Correctness  (** The code is wrong. Error, on by default. *)
    | Suspicious  (** Probably wrong or misleading. Warning, on. *)
    | Perf  (** Needlessly expensive. Warning, on. *)
    | Style  (** Contrary to house idiom. Warning, off by default. *)
    | Pedantic  (** Defensible but strict. Warning, off by default. *)
    | Restriction
        (** Legitimate code, restricted by house policy. Warning, off — and
            outside [all]; cherry-picked. *)

  val all : t list
  (** [all] is every group, in declaration order. The selection vocabularies
      (token parsing, did-you-mean candidates, config name checking) derive from
      it, so a new group lands in each by construction. *)

  val to_string : t -> string
  (** [to_string g] is [g]'s lowercase name as used in configuration and
      selection — e.g. ["correctness"]. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf g] formats {!to_string}. *)
end

(** Render-time severity, derived from the group. *)
module Severity : sig
  (** The type for severities. Severity is never per-finding data: it is the
      emitting rule's group's policy at render time. *)
  type t = Error | Warning  (** *)

  val of_group : Group.t -> t
  (** [of_group g] is the severity of [g]'s findings: [Error] for
      [Group.Correctness], [Warning] otherwise. This is the one severity
      channel: the engine derives every finding's render-time severity as
      [of_group (group r)] of its emitting rule. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf s] formats [s] in lowercase — ["error"] or ["warning"]. *)
end

(** Stability tiers. *)
module Stability : sig
  (** The type for stability tiers. *)
  type t =
    | Stable  (** Subject to group policy; the default. *)
    | Nursery
        (** Off regardless of group until graduated by a reviewed corpus diff;
            selected by [select = ["nursery"]]. Graduation changes neither name
            nor group. *)

  val to_string : t -> string
  (** [to_string s] is [s]'s lowercase name as used in configuration and
      selection — e.g. ["nursery"]. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf s] formats {!to_string}. *)
end

type group = Group.t =
  | Correctness
  | Suspicious
  | Perf
  | Style
  | Pedantic
  | Restriction
      (** The type for groups, equal to {!Group.t}. The equation puts the
          constructors in scope at [Rule]'s top level, so [~group:Rule.Perf]
          compiles under strict warning sets ([-w +40+42]) without opening
          {!Group}. *)

type availability = Fix.availability =
  | Never
  | Sometimes
  | Always
      (** The type for fix promises, equal to [Fix.availability] — re-equated
          here for the same reason: [~fix:Rule.Never] is nameable where a rule
          is declared. *)

(** {1:meta Metadata} *)

type meta
(** The type for rule metadata — the one declaration every surface derives from.
*)

val meta :
  name:string ->
  ?renamed_from:string list ->
  group:group ->
  ?stability:Stability.t ->
  since:string ->
  fix:availability ->
  summary:string ->
  doc:string ->
  ?requires_options:bool ->
  ?kind_gated:bool ->
  unit ->
  meta
(** [meta ~name ~group ~since ~fix ~summary ~doc ()] is a rule's metadata.

    - [name] is kebab-case ASCII, stable forever, and the rule's identity
      everywhere — config, suppression attributes, output. Third-party rules
      render as [org/rule-name].
    - [renamed_from] lists tombstone aliases from prior names, honored by config
      validation and [allow]/[expect] matching with a rename warning. Defaults
      to [[]].
    - [stability] defaults to [Stability.Stable].
    - [since] is the release that introduced the rule, e.g. ["1.0"].
    - [fix] is the fix promise, enforced by the rule test suites and at registry
      construction (see {!Fix.availability}).
    - [summary] is the one-line description shown by [litany rules].
    - [doc] is Markdown: the rule's full documentation, rendered by
      [litany explain] and the docs site. House shape: what fires, why it
      matters, a bad/good pair, and what deliberately does not fire.
    - [requires_options] (default [false]) declares that the rule is inert until
      a config [(rule <name> ...)] form supplies its options — a configured
      policy with no built-in list. The check driver warns when such a rule is
      selected with no form: selected-but-unconfigured is the mirror of the
      configured-but-unselected trap, and both are enumerated.
    - [kind_gated] (default [false]) declares that the rule's callback gates on
      roster metadata — the unit's stanza kind or visibility
      ([Unit.kind]/[Unit.visibility]) — and degrades to silence where the roster
      carries none. In a run whose roster carries no kind at all (the artifact
      walk, a metadata-less unit file) the engine reports the rule inactive on
      the withheld channel ([Engine.Report.withheld_rules]) so structural
      silence is enumerated, never read as a clean corpus.

    Raises [Invalid_argument] if [name] (or an alias) is not kebab-case, or
    [summary] is empty. *)

(** {1:rules Rules}

    Constructors fix the callback's node type; each subscribes the rule to
    exactly that kind. The typed kinds see the compiler's own post-expansion
    trees; [attribute] sees the engine's pre-PPX parse of the editable source;
    [source] sees raw text. Callbacks must be pure: no IO, no mutation outside
    their own scope — the cache and parallel sharding assume it. *)

type t
(** The type for rules. *)

val expr : meta -> (Unit.t -> Typedtree.expression -> Finding.t list) -> t
(** [expr m f] is the rule [m] whose [f] is dispatched at every expression of
    each unit's typedtree, in one engine-owned traversal. *)

val pattern : meta -> (Unit.t -> Typedtree.pattern -> Finding.t list) -> t
(** [pattern m f] is the rule [m] dispatched at every value pattern of the
    typedtree. *)

val binding : meta -> (Unit.t -> Typedtree.value_binding -> Finding.t list) -> t
(** [binding m f] is the rule [m] dispatched at every value binding of the
    typedtree. *)

val type_decl :
  meta -> (Unit.t -> Typedtree.type_declaration list -> Finding.t list) -> t
(** [type_decl m f] is the rule [m] dispatched at every type-declaration group
    of the typedtree — each [Tstr_type] item, at the unit's root and inside
    nested structures alike — with the group's declarations in source order. The
    group is the dispatch unit because it is the smallest node at which both
    group-shaped questions ([and]-chain structure) and per-declaration questions
    are well-posed; a singleton group is the common case and costs one callback
    either way. Interface trees ([Tsig_type]) are not dispatched: rules run over
    implementations, and findings anchor in the editable source — interfaces are
    deliberately not a substrate, and revisiting that means adding a module-type
    rule kind, not extending this one. On compilers with expression-local type
    groups ([type t = … in e], 5.5's [Texp_struct_item]) those groups dispatch
    here too, as ordinary groups. Unlike {!let_group} the callback carries no
    keyword location and no [rec] flag: four tenants in, none had read them — a
    [nonrec]-family rule re-adds the flag additively when it ships. *)

val let_group :
  meta ->
  (Unit.t ->
  loc:Location.t ->
  Asttypes.rec_flag ->
  Typedtree.value_binding list ->
  Finding.t list) ->
  t
(** [let_group m f] is the rule [m] dispatched at every value-binding group of
    the typedtree — structure-level ([Tstr_value]) and expression-level
    ([Texp_let]) alike — with the group's [rec] flag and its whole location
    ([loc] starts at the [let] keyword: the structure item's loc, or the
    let-expression's). The [binding] kind sees one binding without its flag or
    siblings; group-shaped rules need the group. Class-body let groups
    ([Tcl_let]) are not dispatched — a known false negative: the [binding] kind
    sees their bindings, this kind does not see the group. *)

(** Module bindings, seam-normalized. *)
module Module_binding : sig
  type t
  (** A module binding, seam-normalized: the [module_binding] record gained
      fields mid-window ([mb_uid]), so rules never touch the record — the churn
      is confined here (the [dep_kind]/[Cstr] pattern). *)

  (** The type for binding positions — where the binding stands, one axis (the
      former [local]/[toplevel] bool pair spelt 4 states for 3 positions, with
      the illegal one fenced by prose). *)
  type position =
    | Toplevel  (** An item of the unit's root structure. *)
    | Nested
        (** An item of a sub-structure or functor body — structure-level, but
            not at the root. *)
    | Local
        (** [let module … in …] ([Texp_letmodule]; from 5.5 the
            [Texp_struct_item]-embedded [Tstr_module], same source form — the
            engine's version seam normalizes both to this view). *)

  val id : t -> Ident.t option
  (** The bound module ident; [None] for [module _ = …]. The join key of
      {!Unit.module_uses}. *)

  val name_loc : t -> Location.t
  (** The binder name's location — the finding anchor. *)

  val loc : t -> Location.t
  (** The whole binding's location. *)

  val position : t -> position
  (** [position mb] is where the binding stands. *)

  val v :
    id:Ident.t option ->
    name_loc:Location.t ->
    loc:Location.t ->
    position:position ->
    t
  (** [v ~id ~name_loc ~loc ~position] is a module-binding view. This is the
      engine's constructor — dispatch plumbing like {!callback}, not rule-author
      surface: rules receive views, they never build them. *)
end

val module_binding : meta -> (Unit.t -> Module_binding.t -> Finding.t list) -> t
(** [module_binding m f] is the rule [m] dispatched at every [Tstr_module]
    binding and every [let module … in …] of the typedtree. [Tstr_recmodule]
    groups are not dispatched in this version — in expression position either.
*)

val export : meta -> (Unit.t -> Unit.Export.t -> Finding.t list) -> t
(** [export m f] is the rule [m] dispatched at every row of the unit's export
    index ([Unit.exports]) — the value, type, module, and exception declarations
    of the unit's exported signature, in signature order. The walk is the
    index's, not a tree traversal, so the engine still owns it: the rows are
    dispatched once per unit after the typed traversal, and the index's demand
    gate holds — a unit pays the interface decode only when an export rule is
    selected. An interface-sourced row's location points into the [.mli], where
    typed findings cannot anchor (the emit contract owns findings to the
    editable source), so a firing rule anchors by joining the row back to the
    implementation's matching declaration — the [missing-printer] seam. *)

val attribute :
  ?names:string list ->
  meta ->
  (Unit.t -> Parsetree.attribute -> Finding.t list) ->
  t
(** [attribute m f] is the rule [m] dispatched at every attribute of the unit's
    pre-PPX parse — including floating attributes. Unavailable (silently, with a
    summary note) in units whose editable source does not parse; see
    {!Unit.parsetree}.

    [names], when given, declares the only attribute names the rule inspects
    (every spelling, e.g. [["warning"; "ocaml.warning"]]) and promises that [f]
    returns [[]] on every other attribute. The engine then demands the unit's
    parse — and dispatches the rule — only when the source can hold one of them:
    an explicitly written attribute spells [\[@] and its name literally in the
    source, so a byte scan is exact for written attributes. The
    parser-synthesized docstring attributes ([ocaml.doc]/[ocaml.text]) have no
    literal spelling — a rule that inspects those must declare no [names] and
    pay the parse of every unit. Defaults to no declaration. *)

val source : meta -> (Source.t -> Finding.t list) -> t
(** [source m f] is the rule [m] called on each of the unit's editable source
    files: its implementation source, and its paired interface source when the
    unit has one ([Unit.interface_source]) — so a companion [.mli] is
    text-linted too. Text rules build their own locations from
    {!Source.position}; the engine reads each source exactly once for all of
    them. Text rules are suppressed only by configuration, never by attributes.
*)

val project :
  meta ->
  collect:(Unit.t -> 'fact list) ->
  report:('fact list -> Finding.t list) ->
  t
(** [project m ~collect ~report] is a cross-module rule: [collect] runs per unit
    — pure, cached per unit — and [report] runs once over the concatenation of
    every unit's facts, in roster order of units and emission order within a
    unit, so its input order is deterministic.

    Facts must be Marshal-safe: no closures, no custom blocks. [project] seals
    each fact as one [Marshal] frame at construction — the encode runs inside
    [collect] itself, so an unmarshalable fact is a deterministic rule failure
    on the emitting unit in every mode (cache on or off, serial or sharded), and
    every payload channel and the report phase hand the same bytes; [report]
    decodes the frames it is handed. There is no other codec: the cache key
    includes the binary digest, so a fact schema change invalidates by
    construction.

    A project rule's claim is universally quantified, so the engine runs
    [report] only when the roster is project-capable, no roster unit is a
    fact-skip, and no two admitted units share a compilation unit name (the
    engine tabulates admitted names itself and blocks every project report on a
    duplicate — [Engine.Report.Ambiguous]); when withheld, the summary names the
    blockers and reasons. [collect] still runs on every admitted unit regardless
    — facts are per-unit contributions, cached and captured like findings — so a
    later run (or the sharded parent) can report over them without
    re-collecting.

    [report]'s findings answer to a reduced emit contract, stated at [Engine]:
    by the time [report] runs the units are dropped, so there is no
    corroboration and no attribute suppression — a directive naming a project
    rule is silently inert — and a finding must anchor at an adapter-supplied
    path itself (typically an export's declaration location carried through the
    facts); ghost locations are dropped and counted. Config's per-path ring
    ([keep]) applies as everywhere. *)

(** {1:queries Queries}

    Accessors over a rule's declaration; every derived surface ([litany rules],
    [explain], config validation, renderers) reads these. *)

val name : t -> string
(** [name r] is the rule's stable name. *)

val renamed_from : t -> string list
(** [renamed_from r] is the rule's tombstone aliases. *)

val group : t -> Group.t
(** [group r] is the rule's group. *)

val is_project : t -> bool
(** [is_project r] is [true] iff [r] was built with {!project}. The withheld
    summary, [litany rules], and the project-rules-unavailable judgment read it;
    the only other constructor distinction any consumer reads is the engine's
    {!callback} view. *)

val stability : t -> Stability.t
(** [stability r] is the rule's stability tier. *)

val since : t -> string
(** [since r] is the release that introduced the rule. *)

val fix : t -> Fix.availability
(** [fix r] is the rule's fix promise. *)

val summary : t -> string
(** [summary r] is the rule's one-line description. *)

val doc : t -> string
(** [doc r] is the rule's full Markdown documentation. *)

val requires_options : t -> bool
(** [requires_options r] is [true] iff [r] declared that it is inert until
    configured (see {!meta}). The check driver's selected-but-unconfigured
    warning reads it. *)

val kind_gated : t -> bool
(** [kind_gated r] is [true] iff [r] declared that its callback gates on the
    roster's kind/visibility metadata (see {!meta}). The engine's
    kind-gated-inactive enumeration reads it. *)

val on_by_default : t -> bool
(** [on_by_default r] is [true] iff [r] is in the default set — [Stable] and in
    a default group ([Correctness], [Suspicious], or [Perf]; group is policy).
    The same predicate {!select}'s [default] token uses: every derived surface
    ([litany rules], [explain], per-path config tokens) must read this one
    declaration, never re-spell it. *)

(** {1:selection Selection}

    Resolution of the driver's [--select]/[--ignore] (and the config file's
    [select]/[extend]/[ignore]) over a catalog. Selection is pre-analysis: an
    unselected rule is not run at all — it costs nothing and its suppression
    audits are withheld (absence of a finding is only evidence when the rule
    looked). *)

val select :
  catalog:t list ->
  select:string list ->
  ignore:string list ->
  (t list * string list, string) result
(** [select ~catalog ~select ~ignore] resolves the two token lists over
    [catalog] and is [Ok (rules, warnings)] — the selected rules in catalog
    order, plus one rename warning per tombstone alias used and one
    cherry-picking warning when [select] carries the bare [restriction] group
    token — or [Error message] on the first unknown token, e.g.
    [unknown rule or group "styel" (did you mean "style"?)]. Unknown names are
    refusals, never silent fallbacks.

    A token is a set name ([all], [default]), a stability tier ([nursery]), a
    group name ({!Group.to_string}), a rule name, or a tombstone alias
    ({!renamed_from}, resolved to its rule with a warning). Each token mentions
    rules: [all] every [Stable] rule outside [Restriction] — {e not} the whole
    catalog: [Nursery] rules are off under every group and set until they
    graduate, and [Restriction] rules are house policies meant to be
    cherry-picked, so the full-catalog audit spells [all,restriction,nursery];
    [default] the on-by-default set — [Stable] rules of [Correctness],
    [Suspicious], and [Perf] (group is policy); [nursery] every [Nursery] rule;
    a group name its [Stable] rules (nursery rules join only by tier or exact
    name) — [restriction] resolves like any group, but its bare presence in
    [select] adds the one warning, which states how many restriction rules the
    token enables (group tokens cover stable rules only, so an all-Nursery tier
    yields an honest "0 of n"); exact-name selection of a [Restriction] rule
    warns nothing. Drivers print the selected count in the summary
    ([Engine.Report.rules_selected]) so a near-empty selection reads as such,
    never as a clean corpus.

    Precedence is specificity: an exact name outranks a group or tier, which
    outranks [all]/[default]. A rule is selected iff its most specific [select]
    mention is strictly more specific than its most specific [ignore] mention —
    at equal specificity ignore wins, and an unmentioned rule is out. An empty
    [select] defaults to [["default"]]; [ignore] defaults to nothing. *)

val suggest : candidates:string list -> string -> string option
(** [suggest ~candidates s] is the nearest candidate within edit distance 2 of
    [s] — the did-you-mean metric behind {!select}'s refusals, config
    validation, and the engine's unknown-rule suppression audit. Ties resolve to
    the lexicographically least candidate; [None] when nothing is near. This is
    [Suggest.suggest], re-exported — the tree has one edit-distance metric, and
    that module documents it. *)

(** {1:options Per-rule options}

    The wiring for the config file's [(rule <name> <options>...)] forms. A rule
    that takes options declares an option schema with {!with_options}: a
    function consuming the form's payload — opaque positioned s-expressions,
    validated by nobody before the owning rule — and returning the reconfigured
    rule, or a positioned error. The driver resolves each config form to its
    catalog rule and calls {!configure} before selection; a config error is a
    refusal (exit 2), never a silent fallback. Most rules take no options and
    declare nothing: {!configure} then refuses any payload with "takes no
    options". *)

module Sexp = Sexp
(** The neutral option payload: the configuration file's positioned
    s-expressions ({!Sexp}), re-exported so a rule's option schema imports
    nothing beyond this module. *)

(** Option-schema errors. *)
module Options : sig
  type error = Sexp.Error.t = {
    line : int;  (** 1-based line of the offending payload text. *)
    col : int;  (** 1-based byte column. *)
    message : string;
        (** The message without position — e.g.
            [rule "line-length" option "mxa" is unknown (did you mean "max"?)].
        *)
  }
  (** The type for option errors: a position into the config file and one
      actionable message. It is the configuration surface's one positioned error
      ({!Sexp.Error} — [Config_file.Error] is the same type), so the driver
      renders it with {!to_string} like any config refusal. *)

  val v : at:Sexp.t -> string -> error
  (** [v ~at message] is the error [message] positioned at [at]'s first byte —
      the constructor rule schemas use. *)

  val to_string : ?file:string -> error -> string
  (** [to_string ~file e] is ["file:line:col: message"], [file] defaulting to
      ["litany"] — [Sexp.Error.to_string]. *)

  val pp : Format.formatter -> error -> unit
  (** [pp ppf e] formats {!to_string} with the default [file]. *)
end

val with_options : (Sexp.t list -> (t, Options.error) result) -> t -> t
(** [with_options schema r] is [r] declaring [schema] as its option schema.
    [schema payload] consumes one config form's payload — every s-expression
    after the rule name, verbatim and in order — and returns the reconfigured
    rule (typically by re-running [r]'s own constructor with the parsed values,
    so the result carries the same schema and can be configured again) or the
    first positioned error. A schema must be total over payloads: an unknown
    key, duplicate key, or malformed value is an [Error] with a suggestion where
    one is near, never an exception. *)

val configure : t -> Sexp.t list -> (t, Options.error) result
(** [configure r payload] applies [r]'s option schema to [payload]. An empty
    [payload] is [Ok r] for every rule; a non-empty payload for a rule that
    declared no schema is an [Error] at the first form —
    [rule "<name>" takes no options].

    Raises [Invalid_argument] if the schema returns a rule whose {!name} differs
    from [r]'s — options reconfigure a rule, they never substitute one. *)

(** {1:seam Engine seam}

    The engine's read side of a rule: the callback its constructor fixed, tagged
    by node kind. This is dispatch plumbing, not rule-author surface — rules are
    built with the constructors above, and only [Engine]'s kind-indexed dispatch
    consumes this view. *)

(** The type for callbacks, one arm per constructor. The [Attribute] arm carries
    the rule's declared attribute interest ({!attribute}'s [names]) — the
    engine's parse demand gate reads it. The [Project] arm carries the two
    phases of {!project} over facts already sealed as [Marshal] frames, one
    [string] per fact ({!project}'s constructor owns the codec ends); the engine
    runs [collect] per admitted unit and [report] once over every unit's frames
    concatenated in roster order, and may only hand a rule frames that its own
    [collect] produced — whether directly, or round-tripped through a payload
    channel whose contract guarantees the same binary image (the cache's
    binary-digest key, a forked worker). *)
type callback =
  | Expr of (Unit.t -> Typedtree.expression -> Finding.t list)
  | Pattern of (Unit.t -> Typedtree.pattern -> Finding.t list)
  | Binding of (Unit.t -> Typedtree.value_binding -> Finding.t list)
  | Type_decl of (Unit.t -> Typedtree.type_declaration list -> Finding.t list)
  | Let_group of
      (Unit.t ->
      loc:Location.t ->
      Asttypes.rec_flag ->
      Typedtree.value_binding list ->
      Finding.t list)
  | Module_binding of (Unit.t -> Module_binding.t -> Finding.t list)
  | Export of (Unit.t -> Unit.Export.t -> Finding.t list)
  | Attribute of
      string list option * (Unit.t -> Parsetree.attribute -> Finding.t list)
  | Source of (Source.t -> Finding.t list)
  | Project of {
      collect : Unit.t -> string list;
      report : string list -> Finding.t list;
    }  (** *)

val callback : t -> callback
(** [callback r] is [r]'s callback, as the engine dispatches it. *)
