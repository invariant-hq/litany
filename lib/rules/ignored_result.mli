(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Result and option values discarded by wildcard bindings.

    Reports a [let _ = e] whose [e]'s head type constructor is canonically
    [Stdlib.result] or [Stdlib.option] — the wildcard silences the value the
    type asks the reader to examine.

    Named bindings, unit-typed discards, other head types, abbreviation heads,
    same-spelling local [result]/[option] declarations, [ignore e], and the
    discard positions compiler warning 10 owns (structure items, sequence
    left-hand sides, loop bodies) stay clean. House policy ([Restriction]:
    deliberate discards are legitimate — the never-through-[_] discipline is a
    workspace's to adopt, off even under [all], cherry-picked). Replacing the
    wildcard requires deciding how to handle the value, so the rule offers no
    fix. *)

val rule : Litany.Rule.t
(** [rule] is [ignored-result]. *)
