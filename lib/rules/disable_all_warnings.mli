(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Attributes that disable every compiler warning.

    Reports [warning] and [ocaml.warning] attributes — attached or floating, on
    the pre-PPX parse — whose string payload is exactly the standalone
    disable-everything specification ["-A"], ["-a"], or ["a"]. Each spelling
    clears warning set [a], OCaml's complete warning set.

    Selective, compound, or enabling specifications, other payload shapes, and
    similarly named attributes stay clean. A finding describes the directive,
    not the final state after sibling or inherited attributes. No fix. *)

val rule : Litany.Rule.t
(** [rule] is [disable-all-warnings]. *)
