(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** References into the outdated [Str] module.

    Reports each [Str] declaration a unit references — one finding per
    referenced declaration per unit, anchored at the first reference and
    counting the rest; a declaration referenced once keeps the plain message.
    [Str] keeps its match state in module-global cells, so concurrent — or
    merely interleaved — matches corrupt [matched_group] and kin; [Re] is the
    replacement. Verified, OCaml 5.5.0 arm64 non-flambda: plain interleaving
    with no threads silently truncates an earlier match's group — wrong data,
    never an exception.

    Identity is the declaration's compilation unit: aliases and [open]s join the
    same cluster, while a project-local [module Str], a functor parameter named
    [Str], and [Re.Str] (declared in Re's own units) stay clean; a vendored unit
    literally named [Str] fires — the documented boundary. In preprocessed units
    the collapse is off and every reference reports individually. Off by default
    even after graduation; no fix, the rewrite is a migration. *)

val rule : Litany.Rule.t
(** [rule] is [outdated-str-module]. *)
