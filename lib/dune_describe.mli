(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Decode of the [dune describe workspace --format csexp --lang 0.1
   --with-deps] reply (internal).

   Pure bytes-to-description decoding, split from [Adapter.Dune] so it
   is testable against a captured reply without spawning dune ([test/unit/test_adapter.ml]
   reaches it as [Dune_describe]); it is not part of the
   gated [Adapter] surface.

   The decode is strict on csexp syntax and on the fields the adapter
   consumes, and tolerant of everything else: unknown top-level items and
   unknown fields inside known items are ignored, so additive dune changes at
   lang 0.1 do not break the adapter. *)

type module_ = {
  name : string;
  impl : string option;  (** Build-tree path of the [.ml], when any. *)
  intf : string option;  (** Build-tree path of the [.mli], when any. *)
  cmt : string option;
  cmti : string option;
}
(* One module of a stanza, with build-tree relative paths as dune reports
   them. *)

type library = {
  name : string;
  local : bool;
  source_dir : string option;
  modules : module_ list;
  include_dirs : string list;
}

type executables = {
  names : string list;
  modules : module_ list;
  include_dirs : string list;
}

type stanza = Library of library | Executables of executables

type t = {
  root : string option;  (** The workspace root, absolute. *)
  build_context : string option;  (** E.g. ["_build/default"]. *)
  stanzas : stanza list;
}

val decode : string -> (t, string) result
(** [decode bytes] is the reply [bytes] describe, or a one-line reason with a
    byte offset. *)
