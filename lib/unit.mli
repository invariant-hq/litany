(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Admitted units: a source file joined with the artifact the compiler proved
    against it.

    A unit is an editable source file paired with the [.cmt] the compiler
    emitted for it, admitted only under a freshness {!Witness}: the digest the
    compiler recorded of the bytes it read equals the digest of the bytes on
    disk. {!type:t} has no other constructor, so a typed finding on unverified
    code is unrepresentable — this is the whole replacement for evidence
    bureaucracy, and it holds or fails identically whoever ran the build. A
    candidate that fails admission is a {!Skip} with an enumerated reason,
    listed in the summary; silence is never ambiguous.

    Litany 1.0 admits implementation units only: every unit has a typedtree
    {!implementation}; the [.cmti], when present, is a companion whose decode is
    demand-gated. Entries without a [.cmt] skip as [Skip.Missing_artifact].

    Rules receive units in their callbacks and read them through the accessors
    here; loading ({!load}) is the driver's business. Substrates beyond the
    typedtree — the pre-PPX {!parsetree}, the interface {!interface} — are
    decoded on first access and cached, so a run pays only for what its selected
    rules subscribe to. *)

(** {1:witness Freshness witnesses} *)

(** The proof a unit was admitted under. *)
module Witness : sig
  (** The type for witness kinds. *)
  type kind =
    | Direct
        (** The digest of the source-tree file the user edits equals
            [cmt_source_digest]. *)
    | Derived
        (** The compiler read a built pp file: the digest matches the entry's
            [preprocessed_source], and build currency held at load time (see
            {!Unit.load}). *)

  type t
  (** The type for freshness witnesses. *)

  val kind : t -> kind
  (** [kind w] is [w]'s kind. *)

  val anchor : t -> string
  (** [anchor w] is the path of the file whose digest matched
      [cmt_source_digest] — the editable source for [Direct], the built
      preprocessed source for [Derived]. [_build] copies are never the anchor,
      except for generated units whose only source is in [_build]. *)

  val source_digest : t -> string
  (** [source_digest w] is the 16-byte raw digest of the {e editable} source
      captured at join time — for [Derived] units too, where the anchor digest
      is the pp file's. It is the write baseline for fixes: an edit is
      discarded, not written, if the file's digest no longer equals it at write
      time. The write-time comparison accepts a match under either digest
      algorithm (MD5 or BLAKE128), exactly as admission does. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf w] formats [w] for debugging. The output is not stable. *)
end

(** {1:skip Skips} *)

(** Admission failures, enumerated.

    Every candidate unit is admitted or is exactly one of these, counted and
    listed in the run summary — a skip is a per-unit non-result, never an error
    that stops the run. Whether a skip additionally aborts the run is policy
    above the loader: a non-empty roster in which every unit skips escalates to
    a refusal — all [Wrong_magic] under one foreign compiler generation naming
    both versions, any other mix with the skip breakdown and a remedy per kind.
*)
module Skip : sig
  (** The type for skip reasons. *)
  type t =
    | Stale
        (** The recorded source digest does not match the bytes of the file the
            compiler read — the source changed since. A rebuild refreshes the
            artifact. *)
    | Wrong_magic of { found : string; expected : string }
        (** The artifact was written by a different compiler version: magic
            [found] where this Litany reads [expected]. Detected before any
            decode; a cheap counted skip (~0.2 ms), the common case in shared
            build stores. *)
    | Missing_source
        (** The entry's source path does not exist or cannot be read. *)
    | Missing_artifact
        (** No admissible artifact: the entry's [cmt] path is absent (also the
            1.0 outcome for interface-only entries), does not exist, or is a
            dangling symlink — normal in artifact directories. Also the outcome
            for a unit whose compiler input was a derived file the entry does
            not name — [-pp] in [cmt_args] with no [preprocessed_source], or a
            recorded source name that is not the supplied source's: the Derived
            witness has no anchor. *)
    | Derived_needs_build
        (** The unit's witness is Derived and no build-currency condition held:
            the editable→pp link is the build system's guarantee, and this run
            had no evidence of it. *)
    | Unreadable of string
        (** The artifact failed to decode after a good magic number —
            truncation, corruption. The string is a one-line detail for the
            summary. A rebuild rewrites the artifact. *)
    | Partial_or_packed
        (** The cmt records a partial implementation or a packed module — shapes
            with no whole typedtree to lint. Not observed in real corpora but
            handled, per the taxonomy's contract that decode never crashes the
            run. *)
    | Modified_during_run
        (** The source's digest changed between join and a later re-check (the
            fix loop re-verifies before every write). *)

  val message : t -> string
  (** [message sk] is the summary phrase for [sk] — the fact, never a remedy:
      e.g. ["stale — the source changed since the compiler read it"]. Remedy
      wording is the driver's, keyed on the constructor — only the driver knows
      which adapter ran, so no dune or command-line vocabulary appears here. For
      [Wrong_magic], known magic numbers render as compiler versions
      (["built by OCaml 5.6; this litany reads 5.5"]); unknown magics render
      verbatim. Stable across patch releases; parsed by no one. *)

  val slug : t -> string
  (** [slug sk] is [sk]'s stable machine name — ["stale"], ["wrong-magic"],
      ["missing-source"], ["missing-artifact"], ["derived-needs-build"],
      ["unreadable"], ["partial-or-packed"], ["modified-during-run"]. The JSON
      [reason] vocabulary and the summary grouping key: unlike {!message},
      parsed by consumers; append-only across releases. *)

  val rank : t -> int
  (** [rank sk] is [sk]'s declaration-order index — the sort key under which
      summary listings group skips by reason, so counts render in taxonomy order
      rather than alphabetically. *)

  val same_generation : string -> string -> bool
  (** [same_generation m m'] is [true] iff magic numbers [m] and [m'] belong to
      the same compiler generation. One generation writes two magics — cmi and
      cmt numbers move in lockstep, and a [.cmt] whose module has no [.mli]
      leads with its embedded cmi block's magic — so a store built by one
      foreign compiler surfaces both ([Caml1999Innn] beside [Caml1999Tnnn]).
      Magics of that standard shape compare by generation number, ignoring the
      cmi/cmt letter; anything else compares byte-equal. The wholesale-mismatch
      escalation's equality over [Wrong_magic.found] — the refusal-side
      counterpart of admission accepting both of this compiler's magics. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf sk] formats {!message}. *)
end

(** {1:units Units} *)

type t
(** The type for admitted units. A value of this type is the proof that its
    source and artifact matched under a freshness witness at load time. *)

val load :
  resolver:Naming.Resolver.t ->
  build_current:bool ->
  Roster.Entry.t ->
  (t, Skip.t) result
(** [load ~resolver ~build_current e] joins [e]'s source with its artifact,
    admitting it under a freshness witness or returning the skip that names why
    not. This is the loader — the one place artifact bytes are read and
    Marshal-decoded, exactly once per unit per run.

    Admission, in order: the artifact's magic number is checked before any
    decode ([Skip.Wrong_magic]; the driver may additionally pre-scan magic
    numbers across the roster to refuse wholesale, naming both compiler
    versions, before any unit loads); the cmt is decoded ([Skip.Unreadable],
    [Skip.Partial_or_packed]); the witness is checked — {e Direct} when the
    compiler read the editable source (no [preprocessed_source] and no [-pp] in
    [cmt_args]; units compiled under [-ppx] alone join Direct too): the editable
    source's digest must equal [cmt_source_digest], else [Skip.Stale] — unless
    the recorded source name's basename is not the supplied source's (compared
    as strings, never resolved as paths): the compiler then read a derived file
    the entry does not name, so the Derived witness has no anchor and the skip
    is [Skip.Missing_artifact], not a staleness claim about a file the compiler
    never read. {e Derived} when the compiler read a built pp file
    ([preprocessed_source] named, or [-pp] in [cmt_args] — the latter without a
    [preprocessed_source] path is [Skip.Missing_artifact], naming the missing pp
    file): the pp file's digest must match ([Skip.Stale] otherwise) {e and}
    [build_current] must hold ([Skip.Derived_needs_build]). The digest algorithm
    is compiler-version-dependent with no in-record discriminator — MD5 before
    the 5.5.0 release, BLAKE128 from it — so the comparison accepts a match
    under either; an accidental 16-byte collision is negligible. Recorded paths
    ([cmt_builddir], [cmt_sourcefile]) are never resolved as filesystem paths:
    build-path prefix mapping makes them fictitious in real artifacts, and the
    adapter-supplied paths are the only anchors.

    [build_current] is the driver's judgment that the build system's editable→pp
    tracking is current, by any of: this run executed the build successfully;
    the run is inside dune with the check alias among the invoking rule's
    dependencies; or [--trust-build] was passed.

    [resolver] is the run's name resolver; the loaded unit's {!scope} extends it
    with the intra-unit bridge built from this unit's own
    [cmt_declaration_dependencies], under the load-bearing filter documented at
    {!Naming.Scope}. *)

(** {1:queries Queries} *)

val path : t -> string
(** [path u] is the editable source path, as adapter-supplied. Findings of [u]
    anchor only in this file. *)

val name : t -> string
(** [name u] is the compilation unit name the compiler recorded — ["Foo"] for
    [foo.ml]. *)

val source : t -> Source.t
(** [source u] is the editable source joined at load time — the exact bytes the
    witness digested. *)

val interface_source : t -> Source.t option
(** [interface_source u] is the unit's paired interface source ([.mli]), read
    once at load time, or [None] when the roster entry named none or the named
    file could not be read. It is the text lane's second file: source rules
    ([Rule.source]) run over it and their findings anchor in it; no other
    substrate derives from it. Unlike {!source} it is not witness-checked — a
    text finding is a claim about exactly the bytes read, so staleness cannot
    place it on unverified code; the driver's end-of-run revalidation re-reads
    it at render like any analyzed source. *)

val witness : t -> Witness.t
(** [witness u] is the proof [u] was admitted under. *)

val generated : t -> string option
(** [generated u] is [Some why] iff [u]'s admitted source identifies itself as
    generated, [why] naming what classified it — ["path ends in .ml-gen"]
    (dune-generated alias modules), or ["line directive names lexer.mll"] when
    its digest-verified bytes carry an OCaml line directive [# N "file"] naming
    an [.mll] or [.mly] file — ocamllex/menhir output by the tools' own
    convention. Line directives naming [.ml] files (cppo, ppx dumps of
    hand-written sources) do not classify: those sources are editable and keep
    linting. Generated units admit normally; the engine gives them the
    facts-only outcome — no findings in files the user cannot edit
    ([Engine.Report.outcome]). The lexical classification stands in until build
    systems can declare their generated outputs to the adapter directly.

    The classification scan is lexical (raw bytes, no string/comment awareness),
    so a hand-written file that merely {e quotes} a directive line in a string
    literal classifies too; the marker exists so that reclassification is never
    anonymous: the engine notes it per unit in the report and [--list-units]
    prints it, making a swallowed finding traceable to its cause. Reasons are
    fixed deterministic bytes. *)

val preprocessed : t -> bool
(** [preprocessed u] is [true] iff [u]'s witness is [Derived] or its [cmt_args]
    carry [-pp] or [-ppx] (dune's [staged_pps] compiles the editable source
    under [-ppx], so such units join Direct but carry a post-expansion tree). In
    preprocessed units {!splice} is [None] and the engine downgrades [Safe]
    fixes to [Unsafe]. *)

(** {1:metadata Project metadata}

    The roster entry's ownership facts, re-exposed with type equations so
    project-rule [collect] callbacks read them without a roster argument — and
    so [Litany.Unit.Public] is a nameable constructor for every facade user. *)

(** The type for library visibility, equal to [Roster.visibility]. [Unknown] is
    treated as [Public] wherever root policy applies. *)
type visibility = Roster.visibility = Public | Private | Unknown

(** The type for stanza kinds, equal to [Roster.kind]. *)
type kind = Roster.kind = Library | Executable | Test

val library : t -> string option
(** [library u] is the owning library's name, if known. *)

val visibility : t -> visibility
(** [visibility u] is the owning library's visibility, as the roster entry
    carried it. *)

val kind : t -> kind option
(** [kind u] is the owning stanza's kind, if known. *)

(** {1:substrates Substrates}

    Each substrate is decoded at most once per unit, on first access, and cached
    in [u] — the demand gate: a run whose selected rules never touch a substrate
    never pays its decode. *)

val implementation : t -> Typedtree.structure
(** [implementation u] is the typedtree of [u]'s implementation — the compiler's
    own post-expansion tree, nothing wrapped. Total: admission guarantees it
    exists. Decoded with the cmt at load time. *)

val interface : t -> Typedtree.signature option
(** [interface u] is the typedtree of [u]'s interface, or [None] when the entry
    named no [.cmti]. Demand-gated: the cmti is read and decoded at the first
    call, then cached — roughly half of decode cost avoided when no selected
    rule needs interface annotations. An unreadable, wrong-magic, or {e stale}
    cmti is [None] with a counted degradation, not a skip of the whole unit: the
    decode is witness-checked against the paired interface source — the cmti's
    recorded source digest must match the {!interface_source} bytes read at load
    — so a cmti that no longer describes the [.mli] on disk degrades rather than
    feeding fabricated rows into interface-sourced analysis ({!exports}). The
    check needs both halves in hand: when the entry names no interface source,
    or the cmti records no source digest, the decode is accepted unchecked —
    stated here, not guessed around. Typed findings cannot anchor in the [.mli]
    (the emit contract owns them to the editable source; only the text lane's
    {!interface_source} findings anchor there, and those never read the cmti —
    the text lane lints the exact bytes it read, witness or no witness). *)

val parsetree : t -> Parsetree.structure option
(** [parsetree u] is the engine's own pre-PPX parse of {!source}, or [None] when
    the editable source does not parse as OCaml (cppo sources and kin — such
    units run typed rules only, with a summary note that attribute rules and
    attribute suppression are unavailable). Demand-gated and cached; the same
    parse serves attribute rules, suppression matching, and the emit contract's
    corroboration. *)

(** {1:slicing Source slicing} *)

val splice : t -> Typedtree.expression -> string option
(** [splice u e] is [e]'s original source text, wrapped in parentheses unless it
    is syntactically atomic — suitable for splicing into a fix replacement. It
    is [None] when [u] is preprocessed or when [e]'s location does not slice
    cleanly out of {!source}; findings then ship without the fix rather than
    with a wrong one. *)

val text : t -> Typedtree.expression -> string option
(** [text u e] is [e]'s original source text exactly as written — no delimiting.
    Suitable only where the replacement position needs none: a lambda body or a
    [match] arm body, which extend to the end of their construct and cannot
    re-associate with what follows. Everywhere an operand position is possible,
    use {!splice}. [None] under the same conditions as {!splice}. *)

val parenthesized : t -> Typedtree.expression -> bool
(** [parenthesized u e] is [true] when [e]'s source slice starts with an opening
    delimiter and ends with a closing one — ['('] and [')'], or the [begin] and
    [end] keywords — because the parser gives a delimited expression a location
    that includes the delimiters the author wrote: in [check (o = None)] and
    [check begin o = None end] alike the comparison spans the delimiters. A fix
    replacing [e]'s whole location with text that is not self-delimiting must
    then parenthesize the replacement, or the enclosing grammar re-associates
    around it ([check (o = None)] rewritten bare becomes
    [check Option.is_none o], which parses as [(check Option.is_none) o]);
    {!delimited} does exactly that. The test is framing only, no pairing scan —
    [(a) = (b)] answers [true] — because a wrong [true] restores a harmless pair
    while a wrong [false] breaks the program. [false] whenever the slice is
    unavailable ({!splice}'s conditions). *)

val delimited : t -> Typedtree.expression -> string -> string
(** [delimited u e text] is [text] prepared to replace [e]'s whole location:
    wrapped in parentheses when [e] is {!parenthesized} and [text] is not
    syntactically atomic (an identifier, a literal, a bracketed form — the
    shapes {!splice} leaves bare), [text] unchanged otherwise. The one seam for
    fix replacements of an expression — an application, an operator expression,
    an [if], a [match] — whatever the author's delimiters enclosed; the fixed
    source parses where the original did. *)

(** {1:identity Identity} *)

val scope : t -> Naming.Scope.t
(** [scope u] is the identity view [Pat] matches [u] under: the run's resolver
    extended with [u]'s intra-unit equivalence (see {!Naming.Scope}). *)

(** {1:uses Use index} *)

val uses : t -> Shape.Uid.t -> Location.t list
(** [uses u uid] is the locations, in traversal order, of the identifier
    expressions of [u]'s implementation whose value description carries the
    declaration UID [uid] — every use of that declaration in the unit, however
    spelled: bare, qualified through a module path, or through an alias. It is
    [[]] when the unit never uses the declaration. The natural join key is the
    UID a variable pattern carries ([Pat.bound_var]), so "is this binding used,
    and where" is one query — the whole-unit visibility per-node rules otherwise
    lack, kept traversal-free on the rule side, and the seam per-unit fact
    collection builds on.

    Demand-gated like the other substrates: the first call traverses the
    implementation once and caches a UID-keyed index; later calls are lookups
    returning the cached lists, allocation-free. Value identifiers only. Ghost
    locations are included — a synthesized use is still a use.

    The bounded, subtree-scoped complement is [Pat.occurs]: an [Ident.same]
    occurrence test over one expression, no index. This index answers the
    whole-unit question by UID; [occurs] answers the local one by ident. *)

val implementations : t -> Shape.Uid.t -> Shape.Uid.t list
(** [implementations u uid] is the definition UIDs of [u]'s implementation that
    the artifact records as implementing the interface declaration [uid] — the
    intra-unit definition-to-declaration bridge ([cmt_declaration_dependencies]
    under the admission filter [Naming.Scope] documents, the same table {!scope}
    extends matching with). [[]] for units without an [.mli] and for
    declarations [u] does not implement. The {!uses} index is keyed by the UIDs
    use sites carry — inside the defining unit those are definition UIDs — so
    "is this interface-sourced export used in its own unit" is [uses u uid]
    joined with [implementations u uid] — the project-rule [collect] query. O(1)
    after load; the bridge is retained from the load-time decode. *)

val module_uses : t -> Ident.t -> Location.t list
(** [module_uses u m] is the locations, in traversal order, of the references in
    [u]'s implementation that mention the module bound as [m]: every [Path.t]
    stored anywhere in the implementation tree that the default iterator
    reaches, matched by [Ident.same] on any component position — root, [Pdot]
    prefix, and [Papply] arguments included — plus the result-type head paths of
    constructor and label descriptions at both expression- and pattern-side use
    sites (a qualified [M.C] or [M.field] stores no path of its own; its
    description's result type does), and the extension constructor's own tag
    path at those same sites (an exception's result type is the predef [exn];
    only the tag path carries the module it is spelled through). The carriers,
    as illustration of that rule rather than its statement: expression
    identifiers, module expressions ([Tmod_ident] — [open], [include], aliases,
    functor arguments, first-class-module packs), module types
    ([Tmty_ident]/[Tmty_alias]), type-constructor references ([Ttyp_constr]) and
    package types, class references, type- and pattern-level opens, and
    extension-constructor references and rebinds. [[]] when the unit never
    mentions the module.

    {b Completeness is load-bearing}: this query's consumers report absence, so
    a missed carrier manufactures a false positive — the inverse of the
    catalog's usual FN-safe direction. The fixture contract demands one use per
    carrier form above. Ghost locations count — a synthesized use is still a
    use. Demand-gated and cached like {!uses}; keyed by [Ident] rather than UID
    because module idents are unit-local and paths carry them directly. *)

(** {1:exports Export index} *)

(** Exported declarations. *)
module Export : sig
  (** The type for exported-declaration kinds. 1.0 indexes value, type, module,
      and exception declarations; module types, classes, and non-exception
      extension constructors ([type t += …]) contribute no rows. Every
      constructor has a tenant: [restricted-public-exception] fires on
      [Exception] rows, [restricted-export-name] polices [Value] and [Type] by
      kind, and dead-code roots span all four. *)
  type kind = Value | Type | Module | Exception

  type t
  (** The type for one exported declaration of a unit. *)

  val uid : t -> Shape.Uid.t
  (** [uid x] is the declaration UID of [x] — the identity use sites in other
      units carry, so the join key against {!Unit.uses} queries and {!Unit.deps}
      rows. Whose UID it is depends on the unit's source case, stated at
      {!Unit.exports}. *)

  val name : t -> string
  (** [name x] is [x]'s dotted path from the unit's top level — ["shout"],
      ["Asc.length"]. The unit qualifier is {!Unit.name}, left to the consumer.
  *)

  val kind : t -> kind
  (** [kind x] is [x]'s declaration kind. *)

  val loc : t -> Location.t
  (** [loc x] is the declaration's location as the signature records it — in the
      interface source for interface-sourced rows, in the implementation for
      derived rows. Exports are fact inputs for project rules; findings still
      anchor only in the editable source, per the emit contract. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf x] formats [x] for debugging. The output is not stable. *)
end

val exports : t -> Export.t list
(** [exports u] is [u]'s exported declarations, in signature order, a module's
    row preceding its members'. The source is one of two cases:

    - {e Interface}: the entry named a [.cmti] and it decodes ({!interface} is
      [Some _]). Rows come from the interface's recorded signature — the same
      signature the unit's cmi carries — so UIDs are the unit's interface
      identities, exactly the UIDs use sites in other units carry, and locs
      point into the [.mli]. An [.mli] that [include]s a foreign signature
      declares values under the foreign unit's interface UIDs; rows report them
      as recorded. Interface-sourced rows inherit {!interface}'s witness check:
      a cmti whose recorded source digest no longer matches the interface
      source's bytes degrades, and rows fall to the Derived case below — never
      to fabricated interface rows.
    - {e Derived}: everything else. Rows come from the signature the compiler
      derived for the implementation. For a unit without an [.mli] these
      definition UIDs {e are} its exported identities — the derived cmi embeds
      them. For an mli-backed unit whose cmti the entry did not name, or whose
      cmti failed to decode or its witness check ({!interface}'s counted
      degradation), the derived rows over-approximate the export surface (values
      the [.mli] hides appear) and carry definition UIDs, not the interface
      identities foreign use sites carry — stated here, never guessed around.

    Module rows recurse into literal sub-signatures only ([Mty_signature]): a
    re-export [module L = List] is one Module row, the aliased contents stay the
    target unit's; named module types and functors are opaque. A module
    ascription mints fresh UIDs and rows report the minted identity, never the
    ascribee's.

    Demand-gated and cached like the substrates: the first call reads the
    already-decoded signature — decoding the cmti via {!interface} in the
    interface case — and later calls return the same list. Deterministic:
    signature order, pinned by the unit's own artifact. *)

(** {1:deps Outgoing references} *)

(** Cross-unit references. *)
module Dep : sig
  type t
  (** The type for one outgoing cross-unit reference. *)

  val unit_name : t -> string
  (** [unit_name d] is the referenced compilation unit's name as the artifact
      records it — ["Stdlib__List"], ["Fix_wit__Wit_sigs"]. *)

  val uid : t -> Shape.Uid.t
  (** [uid d] is the referenced declaration's UID — the join key against the
      target unit's {!Export.uid}s. Always a declaration the artifact's tables
      pin; references resolved only to a unit, never to a declaration, are not
      rows at all but names in {!Unit.unit_refs}. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf d] formats [d] for debugging. The output is not stable. *)
end

val deps : t -> Dep.t list
(** [deps u] is [u]'s outgoing item-level cross-unit references — every foreign
    {e declaration} [u]'s own artifact records it touching — deduplicated by UID
    and sorted by unit name, then UID. Three recorded sources, one list:

    - {e Declaration dependencies}: both sides of every recorded pair whose UID
      belongs to another unit — the foreign interface items an [.mli] [include]
      declares through, the foreign definition a module ascription binds.
    - {e The use index}: the value identifiers of the implementation whose
      declaration UID belongs to another unit — {!uses}' own keys, the
      item-level rows a dead-code join matches against the target unit's
      exports.
    - {e Ident occurrences}: occurrence reductions the compiler resolved to
      foreign declaration UIDs (an alias chain contributes every step).

    Every row's {!Dep.uid} pins a declaration; references the artifact records
    only at unit granularity are {!unit_refs}, never rows here. Same-unit,
    predefined, and locally-minted identities never appear.

    Demand-gated and cached: the first call scans the two tables retained from
    the load-time decode — released once the rows are built — and builds the
    {!uses} index if no call has yet; later calls return the cached rows.
    Deterministic by the sort above, whoever ran the build. *)

val unit_refs : t -> string list
(** [unit_refs u] is the names of the compilation units [u]'s artifact records
    it referencing {e without pinning a declaration}, deduplicated and sorted —
    the unit-level residue of the {!deps} scan. Two sources: a reference the
    compiler resolved to a unit's own [Compilation_unit] identity, and each unit
    an {e unresolved} occurrence shape names — the compiler's own reduction is
    local, so a cross-unit projection like [List.length] stays unresolved in the
    artifact, naming its head unit ([Stdlib]) and no declaration. These names
    keep such references honest: a consumer reporting absence over {!deps} joins
    must treat a unit named here as touched. "Which units does [u] touch" is
    this list unioned with the {!deps} rows' {!Dep.unit_name}s. Same-unit names
    never appear; demand-gated and cached with {!deps} (one scan computes both).
*)
