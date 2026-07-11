(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Pure reachability solver for the dead-code project rule.

    [Dead_code_solver] is the terminal computation of the built-in [dead-code]
    rule's [report]: given a complete fact universe — declarations with explicit
    roots, and directed uses edges between them — it returns the declarations
    unreachable from every root, in deterministic order.

    The solver is a plain function over complete inputs. It holds no state,
    reads nothing, and never looks at paths, sources, or configuration; calling
    it again with a fresh universe is the whole incremental story. Reachability
    is forward closure from the roots, so mutually recursive islands that no
    root reaches — the case that requires provisional-dead cycle handling in
    liveness-counting designs — are unreachable by construction.

    Identity is the compiler's: {!Uid.t} {e is} [Shape.Uid.t], so the
    [dead-code] rule feeds [Unit.exports] and [Unit.deps] rows straight in;
    {!Decl.owner} is the owning unit's adapter path (any string key works — the
    solver only compares it), and roots are computed by the caller from roster
    metadata before facts reach the solver. *)

(** {1:facts The fact universe} *)

module Uid : sig
  (** Stable declaration identity — the compiler's [Shape.Uid.t].

      Totally ordered, compared structurally. The type equation is public so
      fact assembly passes declaration UIDs through unchanged; {!v} mints
      synthetic identities (test universes, the dead-code rule's unit-level
      nodes) in the [Compilation_unit] namespace. *)

  type t = Shape.Uid.t
  (** The type for declaration identities. *)

  val v : string -> t
  (** [v s] is the synthetic identity spelled [s] — the compilation-unit UID of
      name [s]. Two {!v} identities are equal iff their spellings are equal, and
      never equal a declaration ([Item]) UID. *)

  val to_string : t -> string
  (** [to_string uid] is [uid] printed by the compiler ([Shape.Uid.print]) — the
      spelling given to {!v} for synthetic identities. *)

  val equal : t -> t -> bool
  (** [equal left right] is spelling equality. *)

  val compare : t -> t -> int
  (** [compare left right] is a total order compatible with {!equal}. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf uid] formats the spelling for maintainers. *)
end

module Decl : sig
  (** One declaration fact. *)

  type t
  (** The type for declaration facts. *)

  val v : uid:Uid.t -> owner:string -> root:bool -> t
  (** [v ~uid ~owner ~root] is the declaration [uid], owned by the compilation
      unit named [owner], live a priori iff [root]. Roots are explicit and
      computed by the caller — public-library exports, executable entry modules,
      [[@litany.root]] annotations — the solver never infers one. *)

  val uid : t -> Uid.t
  (** [uid decl] is the declaration's identity. *)

  val owner : t -> string
  (** [owner decl] is the owning compilation unit's name. *)

  val is_root : t -> bool
  (** [is_root decl] is [true] iff the declaration is an explicit root. *)

  val equal : t -> t -> bool
  (** [equal left right] compares all three fields. *)

  val compare : t -> t -> int
  (** [compare left right] orders by owner, then uid, then root flag, and is
      compatible with {!equal}. This is the report order. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf decl] formats all three fields for maintainers. *)
end

module Edge : sig
  (** One directed uses fact: the body of [user] depends on [used]. *)

  type t
  (** The type for uses facts. *)

  val v : user:Uid.t -> used:Uid.t -> t
  (** [v ~user ~used] is the fact that [user]'s body uses [used]. *)

  val user : t -> Uid.t
  (** [user edge] is the depending declaration. *)

  val used : t -> Uid.t
  (** [used edge] is the depended-upon declaration. *)

  val equal : t -> t -> bool
  (** [equal left right] compares both endpoints. *)

  val compare : t -> t -> int
  (** [compare left right] orders by user, then used, and is compatible with
      {!equal}. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf edge] formats both endpoints for maintainers. *)
end

(** {1:solving Solving} *)

val unreachable : decls:Decl.t list -> edges:Edge.t list -> Decl.t list
(** [unreachable ~decls ~edges] is every declaration in [decls] that no root
    reaches, in {!Decl.compare} order.

    Reachability is the least set that contains every root declaration and,
    whenever it contains an edge's user, also contains that edge's used
    declaration. Self-references and cycles need no special treatment under this
    definition: a mutually recursive island is reported whole unless some root
    reaches into it.

    The universe is the caller's obligation and is taken as complete:

    - Duplicate facts are merged. Two declarations of the same uid must agree on
      [owner] — the merged declaration is a root iff either duplicate is
      ([Invalid_argument] on an owner conflict, spelling both owners). Duplicate
      edges are deduplicated.
    - An edge naming a uid absent from [decls] is ignored: an unknown user
      cannot be reachable, and an unknown used declaration cannot be reported.

    Determinism: the result depends only on the set of facts, never on input
    order. The function allocates its own indexes on every call and keeps no
    state between calls. *)
