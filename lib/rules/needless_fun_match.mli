(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [fun x -> match x with …] that is [function] in longhand.

    Reports functions whose whole body is a match on the final parameter —
    unlabeled, non-optional — when no case guard or body uses that parameter:
    the binding adds nothing, and [function] says the same thing without it.
    Case-side rebindings of the same name are different identities and do not
    block.

    Labeled parameters, scrutinees that are not the bare parameter, scrutinees
    carrying an explicit type constraint (the annotation is load-bearing and
    [function] has nowhere to put it), matches that are only part of the body,
    and matches with [exception] cases deliberately do not fire. No automatic
    fix in this release — the promise flips to [Sometimes] when the
    drop-parameter rewrite lands. *)

val rule : Litany.Rule.t
(** [rule] is [needless-fun-match]. *)
