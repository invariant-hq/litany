(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Attribute suppression: the [allow]/[expect] directives one unit's pre-PPX
    parse declares.

    A policy is compiled from the engine's own parse of the editable source
    ([Unit.parsetree] — never a second parse): every
    [[\@litany.allow "rule: reason"]] and [[\@litany.expect "rule: reason"]]
    attribute becomes a {!Directive.t} scoped to the byte span of the node it is
    attached to, the floating forms ([[\@\@\@litany.allow …]]) scope to the rest
    of the file, and every [litany.]-namespaced attribute that fails the payload
    grammar becomes a {!Malformed.t}. Matching is byte-span containment
    ([Span.includes]) against finding spans, so suppression works even when a
    PPX rewrites the node away — the directive lives in the source the user
    edits, not in the expanded tree.

    The module is pure syntax: it parses payloads and computes scopes, and knows
    nothing of rule registries. Whether a directive's rule name is known,
    selected, renamed, engine-owned, or attribute-suppressible at all is the
    engine's judgment, made through the [rule] predicate of {!covering} and over
    {!directives} when it emits the audit findings ([unused-allow],
    [unfulfilled-expect]).

    {b Payload grammar.} One string literal, ["rule-name: reason"]: a rule name,
    a colon, and a mandatory reason. Horizontal whitespace around both parts is
    trimmed; the reason must be one non-empty line. Anything else is a
    {!Malformed.t} with the problem named — malformed policy never matches and
    never disappears silently.

    {b The boundary: sources that do not parse.} This module's whole substrate
    is the pre-PPX parse, so a unit whose editable source is not OCaml syntax —
    cppo conditionals and kin — has {e no} attribute suppression: there is no
    tree to attach a directive to, and no honest byte span to scope one by (the
    compiler's offsets there count preprocessed bytes the directive never saw).
    That is a boundary, not a gap to engineer around: per-line or comment-based
    directives would re-introduce exactly the offset trust the emit contract
    refuses. The instrument for non-parsing files is configuration — the
    [litany] file's [per-path] ignore selects their reports away by path — and
    the engine already counts such units degraded, so the reduced guarantee is
    named in the summary rather than silently absorbed.

    {b Attachment.} A directive scopes to the parse node carrying its attribute:
    expressions, patterns, value bindings, type declarations and extensions,
    module bindings and declarations, opens, includes, primitives, and item
    payloads — the carriers of the core, module, and type languages. A [litany.]
    attribute on a carrier outside that set (class declarations, object fields)
    scopes to the attribute's own span: it can then match nothing, so the
    engine's audit surfaces it rather than it rotting silently. A floating
    attribute inside an embedded signature ([sig … end]) is outside the set the
    same way — the rest-of-file scope belongs to the structure's floating form
    ([Pstr_attribute]) only, even from inside a submodule [struct … end]. *)

(** {1:directives Directives} *)

(** Valid directives. *)
module Directive : sig
  (** The type for directive kinds — the promise the attribute makes. *)
  type kind =
    | Allow  (** Hide matching findings. *)
    | Expect  (** Hide matching findings and require at least one. *)

  type t
  (** The type for directives: one well-formed [allow]/[expect] attribute, its
      payload parsed and its scope computed. *)

  val kind : t -> kind
  (** [kind d] is [d]'s kind. *)

  val rule : t -> string
  (** [rule d] is the rule name exactly as written in the payload — resolution
      (canonical names, tombstone aliases, unknown names) is the engine's. *)

  val reason : t -> string
  (** [reason d] is the mandatory reason, horizontal whitespace trimmed. *)

  val scope : t -> Span.t
  (** [scope d] is the byte span [d] covers: the attached node's span (which
      includes the attribute itself where the parser extends the node's location
      over it), or \[start of the attribute; end of file) for the floating form.
  *)

  val span : t -> Span.t
  (** [span d] is the attribute's own span — where audit findings anchor. Spans
      are unique per attribute, so this is also a directive's identity. *)

  val deletion : source:string -> t -> Span.t
  (** [deletion ~source d] is the span a fix deleting [d]'s attribute should
      remove from [source] — the unit's editable source, the bytes {!span} was
      computed against: the attribute's own span widened over the horizontal
      whitespace (spaces and tabs) immediately before it, and, when that leaves
      the attribute alone on its line, over the line's ending too (LF or CRLF,
      or to end of file), so a directive on its own line deletes the whole line
      and a trailing one leaves no trailing blanks behind. The engine builds the
      [unused-allow] audit's deletion fix from it; deleting an attribute never
      changes program behavior, so the fix is safe by construction. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf d] formats [d] for debugging. The output is not stable. *)
end

(** {1:malformed Malformed declarations} *)

(** Recognized [litany.] attributes that cannot participate in matching. *)
module Malformed : sig
  (** The type for rejection reasons. *)
  type problem =
    | Unknown_name of string
        (** A [litany.]-namespaced attribute that is neither [litany.allow] nor
            [litany.expect] — the carried string is the written name. *)
    | Not_a_string  (** The payload is not a single string literal. *)
    | Missing_colon  (** No [':'] separates rule name and reason. *)
    | Missing_rule  (** Nothing before the [':']. *)
    | Missing_reason  (** Nothing after the [':'] — reasons are mandatory. *)
    | Invalid_reason
        (** The reason spans lines or carries control characters. *)

  type t
  (** The type for malformed declarations. *)

  val kind : t -> Directive.kind option
  (** [kind m] is the kind the attribute's name declared, or [None] for
      {!Unknown_name} — the engine reports a kind-less malformation under the
      [allow] audit. *)

  val problem : t -> problem
  (** [problem m] is why the declaration was rejected. *)

  val span : t -> Span.t
  (** [span m] is the attribute's own span — where the audit finding anchors. *)

  val message : t -> string
  (** [message m] is the user-facing phrase for [m] — e.g.
      ["malformed allow payload — missing \":\" (expected \"rule-name:
       reason\")"]. For {!Unknown_name} it suggests the nearest reserved name
      (["unknown attribute \"litany.alow\" (did you mean \"litany.allow\"?)"]).
      Stable across patch releases; parsed by no one. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf m] formats {!message} and the span for debugging. The output is
      not stable. *)
end

(** {1:policy Policies} *)

type t
(** The type for one unit's compiled suppression policy. *)

val of_structure : source_length:int -> Parsetree.structure -> t
(** [of_structure ~source_length tree] compiles the policy [tree] declares.
    [tree] must be the pre-PPX parse of the unit's editable source and
    [source_length] that source's byte length — the floating form's scope runs
    to it (a [source_length] shorter than a floating attribute is clamped so the
    scope stays a valid span; the match then finds nothing and the audit
    surfaces it). Attributes outside [litany.]'s namespace are ignored. *)

val directives : t -> Directive.t list
(** [directives p] is the valid directives in source order of their attributes.
*)

val malformed : t -> Malformed.t list
(** [malformed p] is the rejected declarations in source order. *)

val covering : t -> rule:(string -> bool) -> Span.t -> Directive.t option
(** [covering p ~rule span] is the winning directive for an occurrence at
    [span]: among the directives whose written rule name satisfies [rule] and
    whose {!Directive.scope} includes [span], the innermost — smallest scope,
    and between equal scopes the later attribute ("later declarations win").
    [None] when no directive covers the occurrence. Pure; marking the winner
    used is the caller's ledger. *)

(** {1:scan The demand scan} *)

val spelled : string -> bool
(** [spelled contents] is [true] iff [contents] can spell a directive: it holds
    both ["\[@"] and ["litany"] as substrings. An explicitly written attribute
    spells ["\[@"] and the token [litany] literally — the dot and the segment
    after it may be separated from the token by blanks or comments, so the dot
    is not part of the needle — so [false] proves the absence of any [litany.]
    attribute; the engine parses a source for suppression only when this holds.
    Conservative: prose mentioning [litany] beside any attribute also answers
    [true], costing one parse, never a wrong answer. *)
