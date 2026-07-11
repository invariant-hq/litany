(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Format literals that hand-quote [%s].

    Reports every typed format literal containing the byte sequence ["\"%s\""] —
    hand-written quotes around [%s] re-implement [%S] minus its escaping. Keyed
    on the compiled format constructor ([CamlinternalFormatBasics.Format],
    global-path identity), so every [format6] consumer is covered uniformly and
    plain strings containing the sequence are structurally excluded.

    The fix replaces each hand-quoted [%s] with [%S] and is Unsafe: [%S] escapes
    its argument where the hand-written quotes do not. *)

val rule : Litany.Rule.t
(** [rule] is [manual-format-quoting]. *)
