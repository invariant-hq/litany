(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The manual-list-recursion scaffold — one home for the machinery the five
    [manual-list-*] rules otherwise copy verbatim: the two recursive-binding
    body shapes, the arity-bounded application splitter, self-call identity, and
    parameter indexing.

    Every contract is the one the per-rule copies documented; each rule keeps
    its own case patterns and classification captures. The scaffold is internal
    to [litany_rules] — not rule-author surface. *)

val cases_shape :
  Litany.Unit.t ->
  Litany.Typedtree.expression ->
  (Litany.Ident.t list
  * Litany.Typedtree.value Litany.Typedtree.case
  * Litany.Typedtree.value Litany.Typedtree.case)
  option
(** [cases_shape u body] matches [body] as a [function]-style binding of zero to
    two explicit parameters whose final [function] has exactly two cases —
    [(params, c1, c2)] in source order. The self-call is later checked through
    the arity-bounded apply views, so shapes whose self-call takes four or more
    arguments are recorded false negatives. The list is the implicit final
    argument. *)

val match_shape :
  Litany.Unit.t ->
  Litany.Typedtree.expression ->
  (Litany.Ident.t list
  * Litany.Path.t
  * Litany.Typedtree.computation Litany.Typedtree.case
  * Litany.Typedtree.computation Litany.Typedtree.case)
  option
(** [match_shape u body] matches [body] as a one-to-three-parameter binding
    whose body is a two-case [match] over an identifier —
    [(params, scrutinee, c1, c2)]. The scrutinized list must later resolve to a
    parameter; same arity bound as {!cases_shape}. *)

val split_apply :
  Litany.Unit.t ->
  Litany.Typedtree.expression ->
  (Litany.Typedtree.expression * Litany.Typedtree.expression list) option
(** [split_apply u e] is [e] as an application of one to three unlabeled,
    evaluated arguments — [(callee, args)] in source order. Labeled, omitted,
    and four-plus-argument applications refuse. *)

val is_id :
  Litany.Unit.t -> Litany.Ident.t -> Litany.Typedtree.expression -> bool
(** [is_id u id e] holds when [e] is an identifier expression resolving to
    exactly [id] — identity, never spelling. *)

val is_selfcall :
  Litany.Unit.t ->
  self:Litany.Ident.t ->
  expected:Litany.Ident.t list ->
  Litany.Typedtree.expression ->
  bool
(** [is_selfcall u ~self ~expected e] holds when [e] applies the bound function
    itself ([self] by identity, so a same-named outer function refuses) to
    exactly the [expected] idents, in order. *)

val index_of : Litany.Ident.t list -> Litany.Path.t -> int option
(** [index_of params path] is the position [path] designates among the explicit
    parameters, if any. *)

val classify :
  nil:('cat Litany.Typedtree.case, unit, unit) Litany.Pat.t ->
  cons:
    ( 'cat Litany.Typedtree.case,
      Litany.Ident.t ->
      Litany.Typedtree.expression ->
      Litany.Ident.t * Litany.Typedtree.expression,
      Litany.Ident.t * Litany.Typedtree.expression )
    Litany.Pat.t ->
  Litany.Unit.t ->
  'cat Litany.Typedtree.case ->
  'cat Litany.Typedtree.case ->
  (Litany.Ident.t * Litany.Typedtree.expression) option
(** [classify ~nil ~cons u c1 c2] classifies a two-case body in either order:
    whichever case matches [nil] fixes the other as the cons case, whose
    captures are the bound tail and its right-hand side. For rules whose cons
    case captures exactly [(tl, rhs)]; rules with richer captures keep their own
    classification. *)
