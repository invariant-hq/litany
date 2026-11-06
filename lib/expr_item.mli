(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** A structure item in expression position, as the engine dispatches it.

    The embedded item is a bare [structure_item], a member of no [structure], so
    the engine's structure-level dispatch never sees it: no double dispatch, and
    [Tstr_recmodule] in expression position stays excluded as at structure
    level. *)

val local_module : Typedtree.expression -> (Ident.t option * Location.t) option
(** [local_module e] is the bound ident and the binder's location when [e] is a
    let-module expression, and [None] otherwise. *)

val type_group :
  Typedtree.expression ->
  (Location.t * Asttypes.rec_flag * Typedtree.type_declaration list) option
(** [type_group e] is the type-declaration group of [e] when [e] is
    [type ... in e'], its location starting at the [type] keyword, and [None]
    otherwise. *)
