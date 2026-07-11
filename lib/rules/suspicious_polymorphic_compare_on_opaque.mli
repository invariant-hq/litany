(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Polymorphic comparison at types whose representation is not canonical.

    Reports applications of [Stdlib]'s comparison primitives ([=], [<>], [<],
    [>], [<=], [>=], [compare], [min], [max]) and structural membership
    functions ([List.mem], [List.assoc], [List.assoc_opt], [List.mem_assoc])
    whose subject's type proves an opaque head: [Hashtbl.t], a cross-unit
    [Set.Make] or [Map.Make] instance, or a [list], [array], or [option] of one.
    Balanced-tree shape and bucket layout depend on history, so structural
    comparison answers about representation, not contents.

    Shadowed operators, the modules' own [equal]/[compare], abbreviation heads,
    physical equality, and partial applications stay clean; same-unit functor
    instances and tuple components are recorded false negatives. No fix: the
    remedy needs the author's choice of comparison. *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-polymorphic-compare-on-opaque]. *)
