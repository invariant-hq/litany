(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The version [litany --version] prints. *)

val current : string
(** [current] is the git tag a release archive was made from, and ["dev"] in a
    checkout. *)
