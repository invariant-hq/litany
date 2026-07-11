(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Comparable abstract types whose interface exposes no printer.

    Reports each abstract type — no manifest, no representation — of the unit's
    interface whose same signature level exposes an [equal : t -> t -> bool],
    [compare : t -> t -> int], or [to_string : t -> string] (shapes checked
    against the type's own identity) and no [pp] (or [pp_<name>]) of type
    [Format.formatter -> t -> unit]. Anchors at the implementation's matching
    toplevel type declaration — the emit contract owns findings to the editable
    source. Units without an interface, evidence-free handle types, and
    same-named printers of other types deliberately do not fire; submodule
    signatures and [include]-satisfied types are recorded false negatives. *)

val rule : Litany.Rule.t
(** [rule] is [missing-printer]. *)
