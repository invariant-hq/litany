(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Tuple patterns, for {!Pat}. *)

val pat_components : Typedtree.pattern -> Typedtree.pattern list option
(** [pat_components p] is the components of the unlabeled tuple pattern [p], in
    source order, and [None] when [p] is no tuple or a component is labeled: a
    labeled tuple is a different shape from the [(a, b)] a rule speaks of. *)
