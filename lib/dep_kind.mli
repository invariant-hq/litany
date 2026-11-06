(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The kind of a dependency between two declarations in a [.cmt]. *)

type kind = Shape.Uid.Deps.kind
(** The type for dependency kinds. *)

val is_definition_to_declaration : kind -> bool
(** [is_definition_to_declaration k] is [true] iff [k] joins a definition to its
    declaration. *)
