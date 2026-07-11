(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Either-digest comparison, the one home of the witness predicate
   (internal): the loader's admission and the applier's fix-time write
   baseline both call it — accept and write agree by construction, not by
   keeping two copies in step.

   [cmt_source_digest] is 16 raw bytes with no in-record algorithm
   discriminator: MD5 before the 5.5.0 release, BLAKE128 from it.
   Admission and the fix-time write baseline both accept a match under either
   algorithm; an accidental 16-byte cross-algorithm collision is negligible.

   Exposed as a plain (non-private) module so the witness logic is unit
   testable ([test/unit] reaches it as [Digest0]); it is not part
   of the gated [Unit] surface. *)

val matches : recorded:string -> string -> bool
(** [matches ~recorded bytes] is [true] iff [recorded] is the MD5 or the
    BLAKE128 digest of [bytes]. *)

val md5 : string -> string
(** [md5 bytes] is the 16-byte raw MD5 digest of [bytes] — the digest the loader
    stores as the fix-time write baseline ([Unit.Witness.source_digest]). *)

val admit : recorded:string -> string -> string option
(** [admit ~recorded bytes] is [Some md5] — the 16-byte MD5 of [bytes], the
    fix-time write baseline — iff [matches ~recorded bytes], and [None]
    otherwise. One digest pass on the MD5 match path, where {!matches} followed
    by {!md5} would digest twice. *)
