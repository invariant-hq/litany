(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The arguments of a [Texp_apply], as the patterns of {!Pat} read them. *)

val unlabeled_all :
  (Asttypes.arg_label * Typedtree.apply_arg) list ->
  Typedtree.expression list option
(** [unlabeled_all args] is every argument, in source order, when each is
    unlabeled and evaluated, and [None] otherwise. *)

val unlabeled_opt_all :
  (Asttypes.arg_label * Typedtree.apply_arg) list ->
  Typedtree.expression list option
(** [unlabeled_opt_all args] is every unlabeled, evaluated argument, in source
    order, skipping optional arguments, omitted or evaluated. A labeled
    argument, or an omitted unlabeled one, is [None]. *)
