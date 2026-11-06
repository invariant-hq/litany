(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** What constructor and label identity need of a description, for {!Pat}. *)

val name : Data_types.constructor_description -> string
(** [name cd] is the constructor's declared name. *)

val res_head : Data_types.constructor_description -> Path.t option
(** [res_head cd] is the head path of the constructor's result type when that
    type is a type constructor, and [None] otherwise. *)

type lbl = Data_types.label_description
(** The type for label descriptions. *)

val lbl_name : lbl -> string
(** [lbl_name l] is the label's declared name. *)

val lbl_res_head : lbl -> Path.t option
(** [lbl_res_head l] is the head path of the label's record type when that type
    is a type constructor, and [None] otherwise. *)

val lbl_mutable : lbl -> bool
(** [lbl_mutable l] is [true] iff the label is [mutable]. *)
