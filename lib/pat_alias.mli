(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Alias patterns, for {!Pat}. *)

val bound_alias :
  Typedtree.pattern -> (string Location.loc * Types.Uid.t) option
(** [bound_alias p] is the alias's name and declaration uid when [p] is
    [p' as x], and [None] otherwise. *)
