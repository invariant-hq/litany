(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [and]-chained types that are not mutually recursive.

    Reports each member of a multi-declaration [type … and …] group that
    participates in no reference cycle with its siblings — false coupling: the
    chain asserts co-dependence the reference graph disproves, and the member
    can stand as its own [type] item. Members of a genuine cycle never fire;
    singleton groups are exempt.

    Edges are by declaration identity ([Ident.same] over [Pident] heads of
    {!Litany.Pat.type_refs}), so same-named outer types never confuse the graph,
    and a multi-declaration [nonrec] group — where no sibling edge can exist by
    construction — reports every member, derived rather than special-cased. No
    fix: extraction reorders declarations. *)

val rule : Litany.Rule.t
(** [rule] is [needless-mutually-recursive-types]. *)
