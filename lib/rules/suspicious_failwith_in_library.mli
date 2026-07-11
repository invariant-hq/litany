(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** [failwith] at a library's API boundary.

    Reports every reference resolving to [Stdlib.failwith] in units whose roster
    kind is [Library], except references lexically enclosed in a [Texp_try] —
    the same-function trampoline shape. Executables and tests are clean by kind;
    kindless units are silent; a shadowing local [failwith] resolves locally and
    never fires. The exemption is meant for tries whose handler matches
    [Stdlib.Failure] alone; pattern-side exception-constructor identity has not
    landed, so any enclosing try exempts — a recorded false negative. House
    policy ([Restriction]: the defect is the escape, which reference-level
    matching cannot prove — off even under [all], cherry-picked). *)

val rule : Litany.Rule.t
(** [rule] is [suspicious-failwith-in-library]. *)
