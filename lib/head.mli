(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The paths a use site stores, for the module-use index of {!Unit}: a
    qualified [M.C] or [M.field] stores only its description's head. *)

val cstr : Data_types.constructor_description -> Path.t option
(** [cstr cd] is the head path of the constructor's result type when that type
    is a type constructor, and [None] otherwise. *)

val cstr_ext : Data_types.constructor_description -> Path.t option
(** [cstr_ext cd] is the extension constructor's own path, and [None] for an
    ordinary constructor. A use's result-type head is the extended type, so the
    module the constructor is spelled through lives only here. *)

val lbl : Data_types.label_description -> Path.t option
(** [lbl ld] is the head path of the label's record type. *)

val package : Typedtree.package_type -> Path.t * Longident.t Location.loc
(** [package pt] is the package type's path and its spelled name. *)
