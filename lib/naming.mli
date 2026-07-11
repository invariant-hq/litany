(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Canonical names and their resolution to declaration UIDs.

    Identity, not spelling: semantic matching in Litany compares the declaration
    [Shape.Uid.t] a use site carries against the UID a {e canonical name}
    denotes. This module owns the three pieces of that story: the name grammar
    ({!Name}), resolution of a name to the UIDs use sites actually carry
    ({!Resolver}), and the per-unit identity view matching consults ({!Scope}).

    Resolution is signature walking over [.cmi] files, each mechanism verified
    against compiled fixtures: read the defining compilation unit's [cmi_sign]
    and walk items by name — [Sig_value] yields [val_uid] ([Sig_type] yields
    [type_uid] in the type namespace); [Sig_module] descends [Mty_signature],
    hops [Mty_alias] to its target (the aliased unit's cmi when the head is a
    persistent unit, the enclosing signature for a local alias), expands
    [Mty_ident] via [Sig_modtype], and descends [Mty_functor] results for
    functor-body names. External use sites carry exactly the UID stored in the
    defining unit's cmi, with or without an [.mli], so the walk cannot disagree
    with them. No [Env], no [Load_path], no compiler-libs global state is
    touched, and only [.cmi] files — which installed dependencies always have —
    are read.

    Documented limits of the matching relation (verified against compiled
    fixtures): a module ascription ([module M : S = List]) mints fresh UIDs —
    [M.length] and [List.length] are distinct identities, each nameable, neither
    matching the other; all instances of a functor application share the functor
    body's interface UIDs, so a canonical name into a functor body matches every
    instance; a functor parameter typed [module type of M] receives M's
    signature with M's declaration UIDs, so uses of the parameter match
    canonical names into M for every instantiation (an explicitly written
    parameter signature mints parameter-local UIDs and stays distinct); values
    not exported through an [.mli] are unreachable by canonical name. *)

(** {1:names Canonical names} *)

(** Canonical names.

    The grammar — the leaf admits a parenthesized-operator form because symbolic
    operator names may themselves contain dots, which a plain dotted split
    cannot carry:

    {v
    name      ::= (uident ".")+ leaf
    uident    ::= an OCaml capitalized identifier
    leaf      ::= lident | "(" symbol ")"
    lident    ::= an OCaml lowercase identifier
    symbol    ::= an OCaml symbolic operator name, verbatim (may contain ".")
    v}

    Every component before the leaf is a module name and the first is a
    compilation unit as spelled at use sites ([Stdlib], not [Stdlib__List]).
    Operators must use the parenthesized-operator form — [Stdlib.(=)],
    [Base.(|.)] — with no whitespace inside the parentheses; the bare form
    [Stdlib.=] is rejected as malformed. A name has at least two components: a
    bare [lident] or [uident] is malformed. *)
module Name : sig
  type t
  (** The type for canonical names. Values are well-formed by construction. *)

  type error =
    | Malformed of { input : string; at : int; reason : string }
        (** The type for name-grammar errors: [input] does not parse at byte
            offset [at]; [reason] says what was expected. *)

  val of_string : string -> (t, error) result
  (** [of_string s] is [Ok n] if [s] parses under the grammar above and
      [Error e] otherwise. The rule test suites treat any rule mentioning a
      malformed name as a failing test; [Pat.ident] raises on the same
      condition. *)

  val to_string : t -> string
  (** [to_string n] is [n]'s canonical rendering — the parse input with the
      parenthesized-operator leaf form. [of_string (to_string n)] is [Ok n]. *)

  val equal : t -> t -> bool
  (** [equal n n'] is [true] iff the names' components are equal. *)

  val compare : t -> t -> int
  (** [compare n n'] orders names lexicographically by component. The order is
      compatible with {!equal}. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf n] formats [n] as {!to_string}. *)

  val pp_error : Format.formatter -> error -> unit
  (** [pp_error ppf e] formats [e] for rule authors, quoting the input and
      pointing at the offending offset. *)
end

(** Module paths — the module-shaped complement of {!Name}.

    The grammar is [uident ("." uident)*]: every component is a module name, and
    the first is a compilation unit as spelled at use sites. A single component
    denotes a whole compilation unit ([Str]); a dotted path denotes a module
    reached by signature walk from its head unit ([Stdlib.Obj]). Where a {!Name}
    denotes one declaration, a module path denotes a {e boundary}: the set of
    declarations reachable through the module — the relation
    {!Scope.matches_module} tests. *)
module Module_path : sig
  type t
  (** The type for module paths. Values are well-formed by construction. *)

  val of_string : string -> (t, Name.error) result
  (** [of_string s] is [Ok p] if [s] parses under the grammar above and
      [Error e] otherwise — the same positioned error shape as
      {!Name.of_string}, rendered by {!Name.pp_error}. *)

  val to_string : t -> string
  (** [to_string p] is [p]'s rendering — the parse input.
      [of_string (to_string p)] is [Ok p]. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf p] formats [p] as {!to_string}. *)
end

(** References — the union of the two identity grammars.

    A reference is what configuration surfaces accept where a rule literal would
    pick one grammar itself: a [path] with a capitalized last component is a
    module path in the grammar of {!Module_path}; any other last component is a
    canonical value name in the grammar of {!Name}. Classification is by the
    last component's shape alone — an operator leaf is never module-shaped,
    since ['('] cannot occur in a module path. A reference is data, total to
    consume: [Pat.of_ref] turns one into the identity pattern it denotes without
    a failure case, where the raising combinators are sugar over literals. *)
module Ref : sig
  (** The type for references. Values are well-formed by construction. *)
  type t =
    | Value of Name.t
        (** A canonical value name, matched as [Pat.ident] matches it. *)
    | Module of Module_path.t
        (** A module boundary, matched as {!Scope.matches_module}. *)

  val of_string : string -> (t, Name.error) result
  (** [of_string s] classifies [s] by its last component and parses it under the
      matching grammar — the same positioned error shape as {!Name.of_string},
      rendered for configuration surfaces by {!pp_error}. *)

  val to_string : t -> string
  (** [to_string r] is [r]'s rendering — the parse input.
      [of_string (to_string r)] is [Ok r]. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf r] formats [r] as {!to_string}. *)

  val pp_error : Format.formatter -> Name.error -> unit
  (** [pp_error ppf e] renders [e] naming the grammar its input was classified
      under — ["malformed module path"] for a module-shaped input,
      {!Name.pp_error}'s rendering otherwise. Configuration surfaces owe their
      users this classified rendering; {!Name.pp_error} always speaks the value
      grammar. *)
end

(** {1:resolving Resolving} *)

(** Per-run name resolution.

    A resolver memoizes canonical-name resolutions over a fixed cmi search path
    for the duration of one run. Resolution reads cmi files on a cache miss —
    the one deliberate IO edge inside the analysis (deterministic given the cmi
    bytes, which are inputs of the run); after the miss, lookups are in-memory.
    A resolver is not safe for concurrent use; parallel workers each hold their
    own. *)
module Resolver : sig
  type t
  (** The type for resolvers. *)

  val create : cmi_dirs:string list -> t
  (** [create ~cmi_dirs] is a resolver searching [cmi_dirs], in order, for cmi
      files named [uncapitalize(unit) ^ ".cmi"]. [cmi_dirs] is the roster's
      [Roster.cmi_dirs] with the toolchain's standard library directory appended
      by the driver; recorded artifact paths ([cmt_builddir] and kin) are never
      consulted. Creation performs no IO. *)

  val resolve : t -> Name.t -> Shape.Uid.t list
  (** [resolve r n] is the declaration UIDs [n] denotes — the interface UID from
      the defining unit's cmi, in a list because tombstoned re-exports can add
      aliases later. It is [[]] when resolution fails: a missing cmi, a name
      absent from the walked signature, an opaque step ([Papply], a first-class
      module), or a cmi that exists but cannot be read. An unresolved name makes
      patterns that mention it match nothing at check time — a workspace without
      [Base] must not error on a rule mentioning [Base.*]; the rule test suites
      alone harden this into a failure.

      The two failure shapes are deliberately not the same event. A {e missing}
      cmi — no [<unit>.cmi] on the search path — is ordinary absence:
      match-nothing, nothing recorded. A cmi that {e exists} on the search path
      but cannot be read (foreign magic, truncation, IO error) also resolves to
      [[]] — matching against bytes Litany cannot decode would be a guess — but
      the failed read is recorded in {!read_failures}, because it silently mutes
      every rule mentioning a name of that unit: the driver must surface it as a
      per-unit degradation, never as a clean run. Reads at most one cmi per
      compilation unit per run (memoized, ~100 µs amortized); repeated calls are
      pure lookups. *)

  val read_failures : t -> (string * string) list
  (** [read_failures r] is the (cmi path, reason) pairs of every cmi [r] found
      on its search path but could not read, in discovery order — one entry per
      compilation unit, however many names resolved against it. Reasons are
      fixed one-line strings (deterministic bytes). Missing cmis never appear:
      absence is match-nothing by design; unreadability is a degradation the
      engine reports through [Engine.Report.degraded], attributed to the unit
      whose analysis first demanded the read. *)

  val resolve_type : t -> Name.t -> Shape.Uid.t list
  (** [resolve_type r n] is {!resolve} in the {e type} namespace: the same
      module walk, with the leaf looked up among the signature's type
      declarations ([Sig_type], yielding the declaration's [type_uid]) instead
      of its values. The name grammar is unchanged — [Stdlib.result],
      [Fix.Outer.t] — and the two namespaces never mix: a value name resolves to
      nothing here, a type name to nothing under {!resolve}. Predefined types
      ([option], [list], [bool], …) are not declared in any cmi and resolve to
      [[]] here; their identity is the predefined path, which
      {!Scope.matches_type} owns. Failure modes and memoization as {!resolve}.
  *)

  val probe : t -> Name.t -> [ `Resolved | `Absent_unit | `Unresolved ]
  (** [probe r n] classifies [n]'s value-namespace resolution, for literal
      audits ([Pat.Registry]): [`Resolved] — {!resolve} is non-empty;
      [`Absent_unit] — [n]'s defining unit has no readable cmi on the search
      path, so nothing can be said about [n] (a workspace without [Base] must
      not fail an audit over a rule mentioning [Base.*]); [`Unresolved] — the
      defining unit's signature is in hand and [n] denotes nothing in it: the
      typo signal the rule harness hardens into a failing test. Same IO and
      memoization as {!resolve}. *)

  val probe_type : t -> Name.t -> [ `Resolved | `Absent_unit | `Unresolved ]
  (** [probe_type r n] is {!probe} in the {e type} namespace ({!resolve_type}),
      with one addition: a predefined type's [Stdlib] spelling ([Stdlib.option],
      …) is [`Resolved] — its identity is the predefined path no cmi declares,
      which {!Scope.matches_type} owns. *)
end

(** {1:scopes Per-unit scopes} *)

(** The identity view one unit is matched under.

    Rule authors never construct or query a scope: the loader builds it
    ([Unit.load]) and [Pat]'s matching consumes it — it is public so [ident]
    states the whole identity relation in one domain.

    A scope pairs the run's resolver with the linted unit's own intra-unit
    equivalence: inside the defining unit itself, use sites carry implementation
    UIDs, so each canonical (interface) UID the linted unit implements is
    extended with that unit's [cmt_declaration_dependencies] reverse image. The
    filter is load-bearing and is the loader's obligation when it builds the
    [intra] function: only [Definition_to_declaration] pairs whose
    {e definition} side is an [Item] of the linted unit with [Impl] provenance
    and whose declaration side is an [Item] with [Intf] provenance (of any unit
    — an [.mli] that [include]s a foreign signature declares its values under
    the foreign unit's interface UIDs) may be admitted. Ascriptions record pairs
    whose definition side is a foreign [Intf] item; admitting them would
    silently rewrite foreign identities, and the filter refuses them on the
    definition side alone. A definition UID of the linted unit occurs only in
    that unit's own tree, so the extension affects matching only inside the unit
    and only for its own definitions. *)
module Scope : sig
  type t
  (** The type for per-unit identity scopes. *)

  val v :
    resolver:Resolver.t ->
    intra:(Shape.Uid.t -> Shape.Uid.t list) ->
    local:Types.signature ->
    t
  (** [v ~resolver ~intra ~local] is the scope resolving names through
      [resolver], extending each resolved UID [u] with [intra u] — the same-unit
      definition UIDs implementing [u] under the filter above — and resolving
      type heads the linted unit itself binds through [local], the unit's own
      signature (its implementation's [str_type] — {!matches_type}'s local-alias
      hop). Units without an [.mli], and canonical UIDs no definition of the
      linted unit implements, have [intra u = []]; a scope for no unit in
      particular (a resolution audit, matching external artifacts alone) passes
      [local = []], under which the head walk stops at persistent units. *)

  val matches : t -> Name.t -> Shape.Uid.t -> bool
  (** [matches sc n uid] is [true] iff [uid] is one of the resolver's UIDs for
      [n] or of their intra-unit extensions. This is the per-node identity test:
      after the first call for [n], a UID equality against a 1–2 element set, no
      IO, no allocation. *)

  val matches_module : t -> Module_path.t -> Shape.Uid.t -> bool
  (** [matches_module sc p uid] is [true] iff [uid] is inside the module [p]
      denotes — a reference reaching through the module. A single-component [p]
      is a whole compilation unit and matches every UID carrying that unit name
      ([Pat.from_unit]'s relation — no cmi is read, so a vendored unit with no
      cmi on the search path still bounds identities). A dotted [p] resolves by
      the {!Resolver}'s signature walk from its head unit: module aliases hop to
      their targets — a persistent alias target is a unit boundary, so
      [Stdlib.Obj] matches every declaration of [Stdlib__Obj] — and in-signature
      submodules contribute their value declaration UIDs, transitively, functor
      results included (functor-body interface UIDs match every instance, as
      {!matches} documents). Value declarations are the boundary: constructors,
      labels, and types of a forbidden module are not value references and stay
      outside it. A path that fails to resolve — a missing cmi, a name absent
      from the walked signature, an opaque step — matches nothing, exactly as
      {!matches}; unreadable cmis are recorded in {!read_failures} identically.
      Per call after the first for [p]: UID and unit-name equalities against the
      memoized boundary. *)

  val read_failures : t -> (string * string) list
  (** [read_failures sc] is {!Resolver.read_failures} of the scope's resolver —
      the engine's channel: after analyzing a unit it reads the failures its
      matching demanded through here and reports the fresh ones as that unit's
      degradation notes. Rules never consult it. *)

  val matches_type : t -> Name.t -> Path.t -> bool
  (** [matches_type sc n p] is [true] iff the type-constructor path [p] — a
      [Types.Tconstr] head — denotes the canonical type [n]. Type use sites
      carry paths, not declaration UIDs, so this relation is path-shaped where
      {!matches} is UID-shaped: either [n] is [Stdlib.x] for a predefined type
      [x] ([option], [list], [bool], …) and [p] is its predefined path, or
      walking [p] through its head unit's cmi ([Sig_type], as
      {!Resolver.resolve_type}) yields a UID in [n]'s resolution.

      A head module bound {e in the linted unit itself} by a plain alias
      ([module M = List]) or a functor application
      ([module SM = Map.Make (String)]) resolves through the scope's [local]
      signature ({!v}) to the underlying declaration, and the walk continues as
      above — functor applications keep the functor body's interface UIDs (the
      documented {!matches} behavior), so [SM.t] reaches [Stdlib.Map.Make.t]'s
      [type_uid]. The head binding is located by ident stamp ([Ident.same]),
      never by name, so when [include] leaves several same-named bindings in the
      unit's signature each use resolves to exactly the binding it was typed
      through. An {e ascribed} local module resolves exactly as its written
      signature does: a named module type carries that module type's interface
      UIDs (a [Map.S]-ascribed instance still matches [Stdlib.Map.Make.t] — [S]
      is [Make]'s own result signature); an inline signature mints unit-local
      identities that match no canonical name.

      Documented limits: abbreviations are not expanded — the head constructor
      is compared exactly as the type checker inferred it; and a path whose head
      is neither a persistent unit nor a [local] module binding of the linted
      unit — a type declared in the linted unit, or a module local to an
      expression — matches no canonical name; the intra-unit extension does not
      apply, because there is no use-site UID to extend to. Per call after the
      first for [n]: a predefined-ident equality, or a memoized-signature walk
      of the path. *)
end
