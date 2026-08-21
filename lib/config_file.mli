(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The [litany] configuration file.

    One file, one closed schema. A [litany] file at the workspace root is
    dune-style s-expressions — [;] comments, bare and ["quoted"] atoms,
    parenthesized forms — and the grammar is closed: an unknown form, unknown
    key, or duplicate is an error with a position and a did-you-mean suggestion,
    never a warning and never a silent fallback.

    {v
    (litany-config 1)                    ; optional version header, first form only

    (lint
     (select default)                    ; groups or rule names; default | all
     (extend style unused-export)
     (ignore manual-eta-lambda)
     (closed-world false))

    (rule line-length
     (max 100))                          ; options are the rule's own, opaque here

    (per-path
     (paths vendor/** third-party/*.ml)
     (ignore all)
     (reason "vendored code"))
    v}

    The domain is pure and IO-free: the driver reads the file and calls
    {!parse}, which validates everything the schema states on its own — form
    shapes, the closed key sets, the glob grammar. Rule and group names live in
    the rule catalog, which this domain does not depend on: {!check_names}
    validates them against caller-supplied vocabularies with the same positioned
    errors, and each [(rule ...)] form's options stay opaque positioned
    {!Sexp.t} values, handed later to the owning rule's declared option schema.

    Positions are 1-based lines and 1-based byte columns into the parsed string,
    the renderer's convention. *)

(** {1:atoms Positioned atoms} *)

type atom = { value : string; line : int; col : int }
(** The type for positioned atoms — a name with the position of its first byte
    in the parsed string. Quoted and bare spellings are equivalent; [value] is
    the unescaped text. *)

(** {1:sexps S-expressions} *)

module Sexp = Sexp
(** Positioned s-expression values ({!Sexp}, re-exported).

    The neutral value type for [(rule ...)] options: {!parse} keeps them opaque
    — any well-formed s-expression is admitted — and the owning rule's declared
    option schema consumes them at wiring time, positions included, so rule-side
    validation reports [file:line:col] too. *)

(** {1:globs Globs} *)

(** Anchored workspace-relative byte globs — [per-path]'s [paths] entries.

    A small Litany grammar, not gitignore syntax:

    {v
    pattern   = component ("/" component)*
    component = "**" | piece+
    piece     = literal | "*" | "?"
    v}

    - The complete canonical workspace-relative path must match; there is no
      implicit leading or trailing [**].
    - [/] matches the canonical path separator only.
    - [*] matches zero or more bytes other than [/] within one component; [?]
      matches exactly one such byte.
    - [**] is legal only as a complete component. A non-final [**] matches zero
      or more complete components; a final [**] matches one or more — so
      [a/**/b.ml] matches [a/b.ml], while [vendor/**] matches [vendor/x.ml] and
      [vendor/a/x.ml] but not the directory spelling [vendor] itself.
    - Matching is case-sensitive byte matching; a dot has no special treatment.
    - Literal text is the atom's bytes; there is no escape for a literal [*] or
      [?]. *)
module Glob : sig
  type t
  (** The type for compiled globs. *)

  val of_string : string -> (t, string) result
  (** [of_string s] compiles [s], or is [Error reason] when [s] is outside the
      grammar: empty or absolute patterns, empty components, [.], [..], NUL,
      backslash, a trailing [/], any component that contains [**] without being
      exactly it ([***], [a**]), or two adjacent [**] components. The reason is
      a short phrase; {!parse} prefixes position and spelling. *)

  val to_string : t -> string
  (** [to_string g] is the spelling [g] was compiled from. *)

  val matches : t -> string -> bool
  (** [matches g path] is [true] iff [g] matches all of [path]. [path] must be
      canonical: nonempty, relative, [/]-separated, with no empty, [.], [..], or
      NUL component. A non-canonical [path] is the caller's infrastructure
      failure, not a non-match.

      Raises [Invalid_argument] if [path] is not canonical. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf g] formats {!to_string}. *)
end

(** {1:errors Errors} *)

module Error = Sexp.Error
(** Positioned configuration errors ({!Sexp.Error}, re-exported): a position and
    one actionable message — e.g.
    [unknown rule "styel" (did you mean "style"?)]. The same type carries a rule
    option schema's refusals ([Rule.Options.error]), so the driver renders every
    config-file error with [Error.to_string] whichever side produced it. *)

(** {1:configurations Configurations} *)

(** One [(rule <name> <options>...)] form. *)
module Rule_options : sig
  type t
  (** The type for per-rule options. *)

  val name : t -> atom
  (** [name r] is the rule's name, positioned. {!parse} checks only that it is
      an atom; {!check_names} resolves it against the catalog. *)

  val options : t -> Sexp.t list
  (** [options r] is the forms after the name, verbatim and in order — opaque
      here, typed by the rule's declared option schema at wiring time. *)
end

(** One [(per-path ...)] form: report selection by path — selection of reports,
    never of analysis. It is not audited and needs no per-site reason; the
    [reason] key documents intent. *)
module Per_path : sig
  type t
  (** The type for per-path selections. *)

  val globs : t -> (atom * Glob.t) list
  (** [globs p] is the [(paths ...)] entries — each spelling with its compiled
      glob, in order. At least one. *)

  val ignored : t -> atom list
  (** [ignored p] is the [(ignore ...)] tokens — rule or group names, [all] — in
      order. At least one. *)

  val reason : t -> string option
  (** [reason p] is the [(reason ...)] string, if given. Read by no report
      surface — it documents intent in the file itself. It stays in the schema
      deliberately: the schema is closed, so dropping the key would turn every
      config carrying it — the manual's own adoption recipes among them — into
      an exit-2 refusal, not a degradation; a documentation key whose deletion
      breaks working configurations earns its row. *)

  val matches : t -> string -> bool
  (** [matches p path] is [true] iff some glob of [p] matches [path]. Same
      contract as {!Glob.matches}, including the raise on a non-canonical
      [path]. *)
end

type t
(** The type for parsed configurations. *)

val empty : t
(** [empty] is the zero-configuration default — what an absent file means:
    version 1, no selection tokens, [closed_world] false, no rule options, no
    per-path selections. *)

val version : t -> int
(** [version c] is the schema version from the [(litany-config <n>)] header, or
    [1] when the header is absent. This litany reads version 1 only. *)

val select : t -> atom list
(** [select c] is [lint]'s [select] tokens in order. Empty when absent — the
    driver's resolution treats that as [default]. *)

val extend : t -> atom list
(** [extend c] is [lint]'s [extend] tokens in order; empty when absent. *)

val ignored : t -> atom list
(** [ignored c] is [lint]'s [ignore] tokens in order; empty when absent. (The
    schema key is [ignore]; the accessor steps aside for [Stdlib.ignore].) *)

val closed_world : t -> bool
(** [closed_world c] is [lint]'s [closed-world], defaulting to [false]: public
    library exports stay dead-code roots. *)

val rules : t -> Rule_options.t list
(** [rules c] is the [(rule ...)] forms in file order, at most one per rule
    name. *)

val per_paths : t -> Per_path.t list
(** [per_paths c] is the [(per-path ...)] forms in file order. *)

(** {1:parsing Parsing and validation} *)

val parse : string -> (t, Error.t) result
(** [parse src] reads a whole [litany] file from [src] — the driver does the IO.
    It is [Error e] on the first problem, top to bottom: lexical errors, then
    per form the closed schema — an unknown form or key (with a did-you-mean
    suggestion when one is within edit distance 2), a duplicate [(lint ...)]
    form, key, or [(rule <name>)] name, a malformed value, an invalid glob.
    [parse] never raises and touches no catalog: rule and group names are
    validated by {!check_names}. *)

val check_names :
  t -> selection:string list -> rules:string list -> (unit, Error.t) result
(** [check_names c ~selection ~rules] resolves [c]'s names against the caller's
    vocabularies and is [Error e] on the first unknown one, with a positioned
    did-you-mean over the same vocabulary — e.g.
    [litany:4:10: unknown rule or group "styel" (did you mean "style"?)].

    - [selection] is every token valid in [select]/[extend]/[ignore] — set names
      ([all], [default]), stability tiers ([nursery]), group names, rule names,
      and tombstone aliases; checked over [lint]'s three lists and every
      [per-path]'s [ignore], in that order.
    - [rules] is every rule name and alias valid as a [(rule <name>)] head.

    The caller builds both from the catalog ([Rule.name], [Rule.renamed_from],
    [Rule.Group.to_string]); precedence and tombstone warnings stay with
    [Rule.select]. *)
