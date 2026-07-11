(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Typed-pattern combinators over the compiler's trees.

    A pattern describes the shape of a typed-tree node in continuation style:
    [('m, 'k, 'r) t] matches a value of type ['m] and, on success, feeds each
    {!__} capture in left-to-right order to a continuation of type ['k] whose
    final answer is ['r]. {!run} tries a pattern against a node; combinators
    build patterns from constructors mirroring [Typedtree] shapes plus {!(|||)}
    alternation.

    The one semantic primitive is {!ident}: identifiers match by resolved
    declaration UID against a canonical name — never by spelling — under the
    unit's identity scope ({!Unit.scope}). [module L = List] therefore matches a
    [Stdlib.List] name, a local [let length] never does, and there is no "is it
    a list?" combinator because the callee's identity already carries the type
    checker's proof.

    Matching is engine-grade: {!run} touches no compiler-libs global state,
    performs no IO, and does per-node work proportional to the pattern —
    identity tests are UID equalities against 1–2 element sets after the run's
    first resolution of each name.

    Patterns are first-class values: build them once, at module initialization,
    and reuse them across nodes — constructing a pattern inside a rule callback
    re-parses every {!ident} name and reallocates the combinator tree at each
    node the rule visits. A hoisted pattern is weakly polymorphic in its
    continuation type and is fixed by its first use; a pattern needed at two
    result types must be a function returning the pattern.

    Naming follows one convention per axis. Control forms are bare words,
    trailing-underscore where OCaml claims the keyword: {!if_}, {!match_},
    {!try_}, {!seq_}, {!let_body}, {!fun_body}. Constructor and literal views
    wear an [e]/[p] prefix for their expression/pattern side: {!enil}, {!esome},
    {!eint}, {!pnil}, {!psome}. Literal views take a payload pattern over the
    literal's value — {!cst} for a known value, {!__} to capture — so no literal
    kind needs a separate test form beside a capture form.

    In 1.0 patterns cover typed trees; attribute rules match raw [Parsetree]
    payloads directly, with {!section-parsed} providing accessors for the
    recurring shapes. The combinator inventory grows with the rules that demand
    it — additions are additive, never breaking.

    {b Placement law.} This module is the rule author's node-{e reading}
    vocabulary: combinators, views, and bounded queries over nodes a rule
    already holds. A view lives in [Rule] iff it is a {e dispatch payload} — a
    value the engine constructs and hands to a rule-kind callback
    ([Rule.Module_binding], [Unit.Export]); everything an author reaches for
    {e inside} a callback lives here. Additions to the surface ship with their
    first consuming rule, not before. *)

(** {1:patterns Patterns} *)

type ('m, 'k, 'r) t
(** The type for patterns matching values of type ['m], with continuation ['k]
    producing ['r]. *)

val run : ('m, 'k, 'r) t -> Unit.t -> 'm -> 'k -> 'r option
(** [run p u x k] is [Some (k c1 ... cn)] if [p] matches [x], where [c1 ... cn]
    are the values captured by [__] (and {!as__}) in left-to-right order, and
    [None] otherwise. [u] supplies the identity scope {!ident} resolves under.

    [k] is applied exactly once, after the whole pattern has matched — an arm
    that ultimately fails, including an abandoned {!(|||)} arm, never applies
    it. *)

(** {1:captures Captures and alternation} *)

val __ : ('a, 'a -> 'r, 'r) t
(** [__] matches any value and captures it. *)

val drop : ('a, 'r, 'r) t
(** [drop] matches any value and captures nothing. *)

val as__ : ('a, 'k, 'r) t -> ('a, 'a -> 'k, 'r) t
(** [as__ p] matches as [p] and additionally captures the matched value itself,
    before [p]'s own captures. *)

val ( ||| ) : ('m, 'k, 'r) t -> ('m, 'k, 'r) t -> ('m, 'k, 'r) t
(** [p ||| p'] matches as [p], or as [p'] when [p] does not match. Both sides
    capture the same types — the continuation cannot tell which arm matched.
    Left-biased: [p'] is not tried when [p] matches. *)

(** {1:expressions Expression patterns} *)

val ident : string -> (Typedtree.expression, 'r, 'r) t
(** [ident name] matches an identifier expression whose resolved declaration UID
    is [name]'s under the unit's scope — see {!Naming.Scope.matches} for the
    exact relation and its documented limits (ascriptions mint fresh identities;
    functor-body names match every instance; a functor parameter typed
    [module type of M] carries M's interface UIDs, so parameter uses match
    canonical names into M whatever the functor is applied to). [name] is a
    canonical name in the grammar of {!Naming.Name}, e.g. ["Stdlib.List.length"]
    or ["Stdlib.(=)"].

    A [name] that fails to {e resolve} at check time makes the pattern match
    nothing — a workspace without [Base] must not error on a rule mentioning
    [Base.*]; the rule test suites alone harden unresolved names into failures,
    so a typo is a failing test, not a silently dead rule. Every accepted name
    is recorded in {!Registry} at construction — the substrate of that audit.

    Raises [Invalid_argument] if [name] does not parse under the canonical-name
    grammar — a programmer error at rule definition time. *)

val idents : string list -> (Typedtree.expression, 'r, 'r) t
(** [idents names] is [ident n1 ||| ... ||| ident nk] — "any of these canonical
    names": left-biased, no captures. Raises [Invalid_argument] on the empty
    list, or on a name that does not parse, as {!ident} does. Checked in that
    order: emptiness first, then each name in list order — the first unparseable
    name raises. *)

val apply :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.expression list, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [apply pf pargs] matches a function application {e all} of whose arguments
    are unlabeled and evaluated — any arity, partial applications included —
    matching the callee against [pf] and the arguments, as one list in source
    order, against [pargs]. Build [pargs] from the
    {{!section-generic}generic views}: [apply pf (px ^:: nil)] is exact arity
    one, [apply pf __] captures the whole argument list — never empty, an
    application node has at least one argument. One labeled or omitted argument
    refuses the whole node. Captures compose left to right: [pf]'s first, then
    [pargs]'s. *)

val apply_opt :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.expression list, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [apply_opt pf pargs] is {!apply} tolerating any number of {e optional}
    arguments — omitted or evaluated — anywhere in the argument list: they are
    skipped, and [pargs] sees only the unlabeled, evaluated arguments. The
    omitted-optional tolerance is the view's whole reason to exist: a saturated
    call to a function carrying [?opt] parameters records the omission in its
    argument list, so the exact-shape {!apply} refuses every such call
    ([Stdlib.Filename.temp_file] and its [?temp_dir] is the first consumer's
    case). A [Labelled] argument, or an omitted {e unlabeled} argument
    (abstraction over an argument), still refuses the node. *)

val cst : 'a -> ('a, 'r, 'r) t
(** [cst v] matches exactly [v] — structural equality — and captures nothing.
    The payload pattern for a known literal value: see {!eint}, {!estring},
    {!ebool}. *)

val eint : (int, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [eint p] matches an integer literal, its value against [p]: [eint (cst 0)]
    matches the literal [0], [eint __] captures the value. Literals only — an
    expression that merely evaluates to an integer does not match. *)

val estring : (string, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [estring p] is {!eint} for string literals, the value compared post-lexing.
*)

val ebool : (bool, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [ebool p] matches either boolean literal — a constructor whose result-type
    head is the predefined [bool] — its value against [p]: [ebool (cst true)]
    matches the literal [true], and [Pat.run (ebool __) u e Fun.id] is the
    one-probe spelling of "is [e] a literal, and which". Literals only;
    expressions that evaluate to a boolean do not match. *)

(** {1:types Type patterns} *)

val typ : string -> (Types.type_expr, 'r, 'r) t
(** [typ name] matches a type whose head constructor denotes, under the unit's
    scope, the canonical type [name] — e.g. ["Stdlib.result"] against a
    discarded expression's [exp_type]. See {!Naming.Scope.matches_type} for the
    exact relation: predefined types are named through [Stdlib]
    ([typ "Stdlib.option"] matches the predefined [option]); abbreviations are
    not expanded, so [type t = int option] has head [t], not [option]; a head
    module the linted unit itself binds by a plain alias or a functor
    application resolves through the unit's own bindings
    ([module SM = Map.Make (String)] makes [SM.t] match ["Stdlib.Map.Make.t"];
    an inline-signature ascription mints fresh identities and never matches —
    the local-alias hop, see {!Naming.Scope.matches_type}); and a type declared
    in the linted unit itself matches no canonical name — type use sites carry
    paths, not declaration UIDs, so identity stops at the cmi boundary.
    Unresolved names match nothing and malformed names raise [Invalid_argument],
    exactly as {!ident}. *)

(** {1:typed-helpers Typed pattern helpers}

    Accessors over [Typedtree.pattern], in the style of {!section-parsed}: not
    combinators, but the recurring shapes rules would otherwise destructure —
    which they must not, where the payload moved across supported compiler
    minors. *)

val bound_var : Typedtree.pattern -> (string Location.loc * Shape.Uid.t) option
(** [bound_var p] is the name, with its source location, and the declaration UID
    of the variable [p] itself binds — a variable pattern [x], or the alias name
    of [p' as x] — and [None] on every other pattern. Shallow by design:
    variables of sub-patterns are not reported, so a rule dispatched at every
    value pattern ({!Rule.pattern}) sees each bound variable exactly once. The
    UID is the join key of [Unit.uses]. The [Tpat_alias] payload changed across
    supported compiler minors; this accessor is the version-stable way to reach
    it. *)

(** {1:generic Generic views}

    Structure-only combinators over lists and options of matchable values. They
    allocate nothing on the refusal path and impose exact shapes:
    [p1 ^:: p2 ^:: nil] matches exactly two elements. *)

val nil : ('a list, 'r, 'r) t
(** [nil] matches the empty list and captures nothing. *)

val ( ^:: ) : ('a, 'k, 'k2) t -> ('a list, 'k2, 'r) t -> ('a list, 'k, 'r) t
(** [p ^:: ps] matches a non-empty list whose head matches [p] and whose tail
    matches [ps]. Captures compose left to right: [p]'s, then [ps]'s. *)

val last : ('a, 'k, 'r) t -> ('a list, 'k, 'r) t
(** [last p] matches a non-empty list whose final element matches [p]. Preceding
    elements are unconstrained and capture nothing. *)

val some : ('a, 'k, 'r) t -> ('a option, 'k, 'r) t
(** [some p] matches [Some v] when [p] matches [v]. *)

val none : ('a option, 'r, 'r) t
(** [none] matches [None]. *)

(** {1:more-expressions Further expression patterns} *)

val var : (Typedtree.expression, Path.t -> 'r, 'r) t
(** [var] matches any identifier expression and captures its resolved [Path.t].
    The typed complement of {!ident}: {!ident} tests a known identity, [var]
    captures an unknown one for rule-side comparison (e.g. [Ident.same] against
    a binding's ident via [Path.Pident]). *)

val from_unit : string -> (Typedtree.expression, 'r, 'r) t
(** [from_unit u] matches an identifier expression whose resolved declaration
    UID belongs to compilation unit [u] — [Shape.Uid.Item {comp_unit = u; _}] or
    [Compilation_unit u]. The unit name is the identity boundary: a local module
    named [u] mints its own UIDs and never matches, while a {e vendored}
    compilation unit spelled [u] does — the same reservation argument as the
    [litany.] attribute namespace. Sugar for {!of_ref} of the one-component
    module path [u] ({!Naming.Ref.Module}). Raises [Invalid_argument] if [u] is
    not a valid module name (a dotted path included: a unit name is one
    component). *)

val of_ref : Naming.Ref.t -> (Typedtree.expression, 'r, 'r) t
(** [of_ref r] is the identity pattern reference [r] denotes: {!ident}'s
    relation for a {!Naming.Ref.Value}, and for a {!Naming.Ref.Module} the
    module-boundary relation of {!Naming.Scope.matches_module} — a single
    component matches any reference into that compilation unit as {!from_unit}
    does, and a dotted path matches any reference reaching through the module it
    denotes (aliases hop, so [Stdlib.Obj] matches every [Stdlib__Obj]
    declaration; in-signature submodules contribute their values transitively).
    Total — a reference is data, well-formed by construction; one that fails to
    {e resolve} in the linted workspace matches nothing, per {!ident}'s
    contract. *)

val reference : string -> ((Typedtree.expression, 'r, 'r) t, string) result
(** [reference path] is the configuration-facing sugar over the data pair:
    {!Naming.Ref.of_string} classifies [path] by its last component and parses
    it under the matching grammar, and {!of_ref} is the pattern.

    Where {!ident} raises on a malformed name — rule-literal names are
    programmer errors — [reference] returns [Error message], rendered by
    {!Naming.Ref.pp_error}: its strings arrive from configuration, so the caller
    owes its user a positioned refusal, not an exception. *)

val enil : (Typedtree.expression, 'r, 'r) t
(** [enil] matches the empty-list constructor expression [[]], by
    predefined-list identity (a user-defined [[]] constructor never matches). *)

val econs :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.expression, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [econs ph pt] matches [h :: t] — the predefined list [(::)] — with [ph] on
    the head and [pt] on the tail. User-defined [(::)] constructors never match.
*)

val esome : (Typedtree.expression, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [esome p] matches [Some v] by predefined-option identity, [p] on the
    argument. *)

val enone : (Typedtree.expression, 'r, 'r) t
(** [enone] matches the [None] constructor expression, by predefined-option
    identity. The expression counterpart of {!pnone}, alongside {!esome}. *)

val eok : (Typedtree.expression, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [eok p] matches [Ok v] — the [Stdlib.result] constructor, identified by its
    result type's head being the global [Stdlib.result] path — with [p] on the
    argument. *)

val eerror :
  (Typedtree.expression, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [eerror p] matches [Error v] — the [Stdlib.result] constructor, identified
    as {!eok} — with [p] on the argument. *)

val if_ :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.expression, 'k2, 'k3) t ->
  (Typedtree.expression option, 'k3, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [if_ pc pt pe] matches [Texp_ifthenelse]: condition against [pc],
    then-branch against [pt], and the {e optional} else-branch against [pe] (use
    {!some}/{!none}/{!drop}). *)

val match_ :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.computation Typedtree.case list, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [match_ ps pcs] matches [Texp_match]: scrutinee against [ps], computation
    cases against [pcs]. Refuses a match carrying effect-handler cases: no rule
    vocabulary speaks about effect handlers, and silently ignoring them would
    let case-shape rules misread a handler as a plain match. *)

val try_ :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.value Typedtree.case list, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [try_ pb pcs] matches [Texp_try]: body against [pb], exception-handler cases
    against [pcs]. Effect-handler cases neither block nor surface — a [try] with
    effect cases still matches, because its exception cases mean what they
    always mean. (Deliberately asymmetric with {!match_}: there the cases
    {e are} the object of study; here they are.) *)

val seq_ :
  (Typedtree.expression, 'k, 'k2) t ->
  (Typedtree.expression, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [seq_ p1 p2] matches [Texp_sequence]: left leg against [p1], right leg
    against [p2]. *)

val let_body :
  (Typedtree.expression, 'k, 'r) t -> (Typedtree.expression, 'k, 'r) t
(** [let_body p] matches [Texp_let], descending into its body with [p]. The
    bindings are not examined — rules that strip statement spines care only
    where the spine ends; a bindings view is added when a rule needs one, not
    before. *)

val fun_body :
  (Typedtree.function_param list, 'k, 'k2) t ->
  (Typedtree.expression, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [fun_body pps pb] matches [Texp_function (params, Tfunction_body b)]:
    parameters against [pps], body against [pb]. [function_param] is matched
    through {!param} — its record fields are not part of the rule vocabulary, so
    field churn across compiler minors stays confined to this module. *)

val fun_cases :
  (Typedtree.function_param list, 'k, 'k2) t ->
  (Typedtree.value Typedtree.case list, 'k2, 'r) t ->
  (Typedtree.expression, 'k, 'r) t
(** [fun_cases pps pcs] matches [Texp_function (params, Tfunction_cases _)]:
    explicit parameters against [pps] (possibly {!nil}), the final implicit
    argument's cases against [pcs]. *)

val format : (Typedtree.expression, string -> 'r, 'r) t
(** [format] matches a compiled format literal — the
    [CamlinternalFormatBasics.Format] constructor the type checker elaborates
    every literal format string into, identified by its result type's head being
    the global [CamlinternalFormatBasics.format6] path — and captures the
    original literal's post-lexing bytes. Plain string literals never match. *)

(** {1:params-cases Parameter and case patterns} *)

val param :
  (Typedtree.pattern, 'k, 'r) t -> (Typedtree.function_param, 'k, 'r) t
(** [param pp] matches an {e unlabeled, non-optional} function parameter
    ([fp_arg_label = Nolabel], kind [Tparam_pat]), its pattern against [pp].
    Labeled and optional parameters refuse — every rule in the catalog treats
    them as a different shape. *)

val case :
  ('cat Typedtree.general_pattern, 'k, 'k2) t ->
  (Typedtree.expression option, 'k2, 'k3) t ->
  (Typedtree.expression, 'k3, 'r) t ->
  ('cat Typedtree.case, 'k, 'r) t
(** [case pp pg pr] matches one case: pattern against [pp], guard ([c_guard], an
    option — use {!some}/{!none}/{!drop}) against [pg], right-hand side against
    [pr]. Polymorphic in the pattern category, so it serves value cases ([try],
    [function]) and computation cases ([match]) alike. *)

(** {1:patterns-t Typed-pattern patterns}

    Views over [Typedtree.pattern] (value patterns) and the computation-pattern
    bridges. Constructor views use the same predefined-type identity as their
    expression counterparts; none of them match through [Tpat_alias] or
    [Tpat_or] — an aliased or or-composed pattern is a different shape and
    refuses. *)

val pany : (Typedtree.pattern, 'r, 'r) t
(** [pany] matches the wildcard pattern [_] — [Tpat_any] exactly, not "matches
    anything": a variable or deeper pattern refuses. *)

val pvar : (Typedtree.pattern, Ident.t -> 'r, 'r) t
(** [pvar] matches a variable pattern and captures its [Ident.t]. The ident is
    the unit of identity for intra-rule comparisons ([Ident.same]); shadowing
    therefore costs rules nothing. *)

val pnil : (Typedtree.pattern, 'r, 'r) t
(** [pnil] matches the empty-list pattern [[]], by predefined-list identity. *)

val pcons :
  (Typedtree.pattern, 'k, 'k2) t ->
  (Typedtree.pattern, 'k2, 'r) t ->
  (Typedtree.pattern, 'k, 'r) t
(** [pcons ph pt] matches the pattern [h :: t], by predefined-list identity,
    [ph] on the head, [pt] on the tail. *)

val pbool : bool -> (Typedtree.pattern, 'r, 'r) t
(** [pbool b] matches the boolean literal pattern [b], by predefined-bool
    identity. *)

val psome : (Typedtree.pattern, 'k, 'r) t -> (Typedtree.pattern, 'k, 'r) t
(** [psome p] matches the pattern [Some v], by predefined-option identity, [p]
    on the argument. *)

val pnone : (Typedtree.pattern, 'r, 'r) t
(** [pnone] matches the pattern [None], by predefined-option identity. *)

val pok : (Typedtree.pattern, 'k, 'r) t -> (Typedtree.pattern, 'k, 'r) t
(** [pok p] matches the pattern [Ok v], by the global [Stdlib.result] path
    identity of {!eok}, [p] on the argument. *)

val perror : (Typedtree.pattern, 'k, 'r) t -> (Typedtree.pattern, 'k, 'r) t
(** [perror p] matches the pattern [Error v], identified as {!pok}, [p] on the
    argument. *)

val pvalue :
  (Typedtree.pattern, 'k, 'r) t ->
  (Typedtree.computation Typedtree.general_pattern, 'k, 'r) t
(** [pvalue p] matches a computation pattern that is a plain value pattern
    ([Tpat_value]), descending into it with [p]. *)

(** {1:tuples Tuple views}

    The tuple payloads ([Texp_tuple], [Tpat_tuple], [Ttyp_tuple]) gained labeled
    components at 5.4 ((string option * _) list; plain lists in 5.3). The view
    is seam-normalized behind a version-selected-copy leg pair
    ([tuple_53.ml]/[tuple_54.ml], the [apply_arg] pattern) and matches
    {e unlabeled} tuples only: one labeled component refuses the node. The
    expression-side twin ([etuple]) ships with its first rule, not before. *)

val ptuple : (Typedtree.pattern list, 'k, 'r) t -> (Typedtree.pattern, 'k, 'r) t
(** [ptuple pps] matches an unlabeled tuple pattern, its components as a list
    against [pps] (component count is the list's length; [Tpat_tuple]'s n >= 2
    invariant holds). Labeled components refuse. *)

(** {1:records Record views}

    [Texp_record]'s shape is stable across the window, but the
    [label_description] record's module home churns with
    [constructor_description] (Types in 5.3, Data_types from 5.4) — the [Cstr]
    seam pattern, extended to labels. *)

(** Label descriptions, seam-normalized. *)
module Lbl : sig
  type t
  (** The type for label descriptions. Rules never touch the underlying record.
  *)

  val name : t -> string
  (** [name l] is the label's declared name. *)

  val res_head : t -> Path.t option
  (** [res_head l] is the head path of the label's record type, when it is a
      type constructor. Two labels with equal {!name} and [Path.same] heads are
      the same label — the identity join [manual-record-update] fires on. *)

  val is_mutable : t -> bool
  (** [is_mutable l] is [true] iff the label is [mutable]. *)
end

(** One field of a record expression. *)
module Field : sig
  type t

  val label : t -> Lbl.t
  (** The field's label. *)

  val definition : t -> Typedtree.expression option
  (** The defining expression for an [Overridden] field; [None] for a [Kept]
      field (which occur only under a [with] extension). *)
end

val erecord :
  (Typedtree.expression option, 'k, 'r) t ->
  (Typedtree.expression, Field.t list -> 'k, 'r) t
(** [erecord pext] matches [Texp_record], capturing its fields (in the record
    type's declaration order — the typedtree does not record source order) and
    matching the optional [with] base against [pext] (use
    {!some}/{!none}/{!drop}). *)

val efield :
  (Typedtree.expression, 'k, 'r) t -> (Typedtree.expression, Lbl.t -> 'k, 'r) t
(** [efield pe] matches a field access [e.l] ([Texp_field]), capturing the
    accessed label and matching the subject against [pe]. The 5.5
    [Texp_atomic_loc] form is a different node and does not match. *)

val pexception :
  (Typedtree.pattern, 'k, 'r) t ->
  (Typedtree.computation Typedtree.general_pattern, 'k, 'r) t
(** [pexception p] matches an [exception]-arm pattern ([Tpat_exception]), its
    payload against [p]. *)

(** {1:queries Queries}

    Not patterns: boolean sub-walks rules combine with pattern results. Each
    walks only the given subtree (a bounded, engine-independent read — rules
    still cannot skip or re-enter the engine's traversal), touches no global
    state, and compares identity by [Ident.same], so a same-spelled rebinding is
    a different ident and does not count as an occurrence. "Occurs" is the
    deliberate word: these are bounded ident-occurrence tests over one subtree,
    where [Unit.uses] is the whole-unit, UID-keyed use index — different scope,
    different identity currency. *)

val occurs : Ident.t -> Typedtree.expression -> bool
(** [occurs id e] is [true] iff an identifier expression resolving to exactly
    [id] ([Texp_ident (Pident id', _, _)] with [Ident.same id id']) occurs in
    [e], at any depth. For the whole-unit question keyed by declaration UID, use
    [Unit.uses]. *)

val case_occurs : Ident.t -> 'cat Typedtree.case -> bool
(** [case_occurs id c] is {!occurs} over the case's guard (if any) and
    right-hand side. The case's own pattern cannot "use" an ident and is not
    scanned. *)

val type_refs : Typedtree.type_declaration -> Path.t list
(** [type_refs d] is the head paths of every type-constructor reference
    ([Ttyp_constr]) in [d]'s parameters, kind, manifest, and constraints, in
    traversal order, duplicates included — a bounded [Tast_iterator] sub-walk
    with the default iterator's coverage (the {!occurs} pattern). The walk is
    the version seam for the constraints field's mid-window rename: rule code
    never names it. *)

(** {1:parsed Parsed helpers}

    Not combinators: plain accessors over the raw [Parsetree] shapes every
    attribute rule re-destructures. They live here because this module is the
    declared home of parsed-side matching. *)

val payload_string : Parsetree.payload -> (string * Location.t) option
(** [payload_string p] is the string constant and its location when [p] is a
    single-string payload — [PStr] of one [Pstr_eval] of a string constant — and
    [None] otherwise. The common shape of [@warning], [@deprecated], and kin. *)

(** {1:registry Name-literal registry}

    Every canonical-name literal the raising combinators accept is recorded at
    combinator construction: {!ident} and {!idents} record into the value
    namespace, {!typ} into the type namespace. The registry has one consumer —
    the rule test harness audits, on every fixture run, that each recorded
    literal still denotes something wherever its defining unit's cmi is present
    ({!Naming.Resolver.probe}), so a typo in an arm no fixture exercises is a
    failing test, not a silently dead arm forever. {!reference}-built patterns
    are configuration, not literals, and are not recorded. Recording happens at
    construction: under the hoisting discipline above, that is module
    initialization, before any parallelism. *)
module Registry : sig
  val names : unit -> Naming.Name.t list
  (** [names ()] is every value-namespace literal recorded since program start,
      deduplicated, in {!Naming.Name.compare} order. *)

  val type_names : unit -> Naming.Name.t list
  (** [type_names ()] is {!names} for the type namespace — {!typ}'s literals. *)
end
